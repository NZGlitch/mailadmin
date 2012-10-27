#!/usr/bin/env ruby

require 'pg'
require 'digest/md5'

require_relative 'config'
require_relative 'classes'

class Connection
	def initialize
		@con = 	PG::Connection.new(
			:host => MailConfig::DB_HOST, 
			:user => MailConfig::DB_USER, 
			:password => MailConfig::DB_PASS, 
			:dbname => MailConfig::DB_DB
		)
	end
	
	def close
		@con.close if @con
	end
	
	def authenticate(email, password)
		
		if email.nil? || email.empty? || password.nil? || password.empty?
			return false
		end
		
		q = @con.query(
			"select id, password from virtual_users where email = '%s';" % 
				@con.escape_string(email))
		
		return false if q.ntuples == 0
		id = q[0]['id']
		hash = q[0]['password']
		
		if Digest::MD5.hexdigest(password) == hash
			return id
		end
		
		return false
		
	end
	
	def login_exists?(lh, domain)
		
		q = @con.query("select count(*) from virtual_users where email = '%s'" %
			@con.escape_string("#{lh}@#{domain.name}") )
		
		return q[0]['count'].to_i > 0
		
	end
	
	def update_password(id, password)
		
		@con.query("update virtual_users set password = '%s' where id = %d;" %
			[ Digest::MD5.hexdigest(password), id ])
		
	end
	
	def get_user(id)
		
		q = @con.query(
			"select virtual_users.*, virtual_domains.id as admin_domain_id, 
			virtual_domains.name as admin_domain_name 
			from virtual_users 
			left join domain_admins on virtual_users.id = domain_admins.user_id
			left join virtual_domains on domain_admins.domain_id = virtual_domains.id 
			or virtual_users.super_admin
			where virtual_users.id = %d order by admin_domain_name desc;" % id)
		
		user = nil
		
		q.each do |row| 
			
			if user.nil?
				user = User.new
				user.id = row['id']
				user.email = row['email']
				user.password = row['password']
				user.domain_id = row['domain_id']
				user.super_admin = row['super_admin'] == "1"
				user.admin_domains = {}
			end
			
			if row['admin_domain_id']
				domain = Domain.new
				domain.id = row['admin_domain_id']
				domain.name = row['admin_domain_name']
				user.admin_domains[domain.id] = domain
			end
			
		end
		
# we do this this way so we don't depend on having goldfish installed
		if test_goldfish
			
			ar = user.autoresponder = AutoResponder.new
			
			q = @con.query("select * from autoresponder where email = '%s'" %
				user.email)
			
			if q.ntuples >= 1
				row = q[0]
				
				ar.email = row['email']
				ar.descname = row['descname']
				ar.from = Date.strptime(row['from'], '%Y-%m-%d')
				ar.to = Date.strptime(row['to'], '%Y-%m-%d')
				ar.message = row['message']
				ar.enabled = row['enabled'].to_i == 1
				ar.subject = row['subject']
				
			end
		end
		
		return user
		
	end
	
	def add_user(lh, domain, password, admin_domains, super_admin)
		
		email = @con.escape_string("#{lh}@#{domain.name}")
		@con.query("insert into virtual_users (domain_id, password, email, super_admin) values (%d, '%s', '%s', %s)" %
			[ domain.id, Digest::MD5.hexdigest(password), email, super_admin ? 'true' : 'false' ])
		
		if admin_domains && admin_domains.length > 0
			id = insert_id
			
			admin_domains.each do |did|
				@con.query("insert into domain_admins values(%d, %d)" % [ did, id ])
			end
		end
		
		@con.query("insert into virtual_aliases values(NULL, %d, '%s', '%s')" %
			[ domain.id, email, email ])
		
	end
	
	def update_user(uid, password, admin_domains, super_admin)
		
		if password.nil? or password.empty?
			password = "password"
		else
			password = "'%s'" % Digest::MD5.hexdigest(password)
		end
		
		sa = super_admin ? 1 : 0
		
		@con.query("update virtual_users set password = %s, super_admin = %d 
			where id = %d;" % [ password, sa, uid ])
		
=begin
TODO by deleting all the existing admin info, we disallow 2 admins with
access to 2 different domains the ability to give the same user access
to domains the other can't see -- it'll delete ones that "I" can't check.
=end

		@con.query("delete from domain_admins where user_id = %d;" % uid)
		
		sql = nil
		admin_domains.each do |did|
			(sql ||= "insert into domain_admins values") << " (#{did}, #{uid})," 
		end
		
		@con.query(sql.gsub(/,$/, '')) unless sql.nil?
		
	end
	
	def delete_user(uid)
		
		user = get_user(uid)
		
		if test_goldfish
			@con.query("delete from autoresponder where email = '%s'" % 
				@con.escape_string(user.email))
		end
		
		@con.query("delete from domain_admins where user_id = %d" % uid)
		@con.query("delete from virtual_aliases where destination = '%s'" % 
			@con.escape_string(user.email))
		@con.query("delete from virtual_users where id = %d" % uid)
		
	end
	
	def domain_users(domain)
		
		q = @con.query("select virtual_users.*, domain_admins.domain_id as is_admin 
			from virtual_users left join domain_admins 
			on virtual_users.domain_id = domain_admins.domain_id
			and domain_admins.user_id = virtual_users.id
			where virtual_users.domain_id = %d order by email asc" % domain.id)
		
		ret = []
		
		q.each do |row|
			
			user = User.new
			user.id = row['id']
			user.email = row['email']
			user.admin_domains = [ row['is_admin'] ]
			
			ret << user
			
		end
				
		return ret
		
	end
	
	def domain_aliases(domain)
		
		q = @con.query("select * from virtual_aliases
			where domain_id = %d and source != destination order by source asc" % domain.id)
		ret = []
		q.each do |row|
			
			a = Alias.new
			a.id = row['id']
			a.source = row['source']
			a.destination = row['destination']
			
			ret << a
			
		end
		
		return ret
		
	end
	
	def add_domain(name, uid)
		
		@con.query("insert into virtual_domains values(NULL, '%s');" % 
			@con.escape_string(name))
		
		id = insert_id
		
		@con.query("insert into domain_admins values(%d, %d);" % [ id, uid ])
		
	end
	
	def delete_domain(id)
		
		@con.query("delete from virtual_users where domain_id = %d;" % id)
		@con.query("delete from virtual_aliases where domain_id = %d;" % id)
		@con.query("delete from domain_admins where domain_id = %d;" % id)
		@con.query("delete from virtual_domains where id = %d;" % id)
		
	end
	
	def get_alias(aid)
		
		q = @con.query("select * from virtual_aliases where id = %d" % aid)
		
		ret = nil
		
		if row = q[0]
			
			ret = Alias.new
			ret.id = row['id']
			ret.source = row['source']
			ret.destination = row['destination']
			ret.domain_id = row['domain_id']
			
		end
		
		return ret
		
	end
	
	def get_alias_by_name(name, field = :src)
		
		f = field == :src ? "source" : "destination"
		
		q = @con.query("select id from virtual_aliases where %s = '%s'" % 
			[ f, @con.escape_string(name) ])
		
		return row[0] if row = q[0]
		
		return nil
		
	end
	
	def add_alias(src_domain, src, dst)
		
		@con.query("insert into virtual_aliases values (NULL, %d, '%s', '%s')" %
			[ src_domain.id, @con.escape_string(src), @con.escape_string(dst) ])
		
	end
	
	def delete_alias(aid)
		@con.query("delete from virtual_aliases where id = %d" % aid)
	end

	def insert_id
		@con.query("select last_insert_id()")[0]
	end
	
	def test_goldfish
		begin
			@con.query("select email from autoresponder limit 1");
			return true
		rescue
			return false
		end
	end
	
	def save_autoresponder(email, descname, from, to, message, enabled, subject)
		
		return false unless test_goldfish
		
		from_str = from.strftime('%Y-%m-%d')
		to_str = to.strftime('%Y-%m-%d')
		
		@con.query("replace into autoresponder values('%s', '%s', '%s', '%s', '%s', %d, '%s')" %
			[ 
				@con.escape_string(email),
				@con.escape_string(descname),
				@con.escape_string(from_str),
				@con.escape_string(to_str),
				@con.escape_string(message),
				enabled ? 1 : 0,
				@con.escape_string(subject)
			]
		)
		
	end
	
	def each_autoresponder
		
		return unless test_goldfish
		
		q = @con.query("select * from `autoresponder` where `enabled` 
			and `from` <= NOW() and `to` > NOW()")
		
		q.each do |row|
			yield row
		end
		
	end
	
	def already_responded?(user, recipient)
		
		return false unless test_goldfish
		
		q = @con.query("select 1 from autoresponder_recipients 
			left join autoresponder 
			on autoresponder_recipients.user_email = autoresponder.email 
			where autoresponder.email = '%s' 
			and autoresponder_recipients.recipient_email = '%s' 
			and autoresponder_recipients.send_date >= autoresponder.`from`" %
				[ @con.escape_string(user), @con.escape_string(recipient) ])
		
		if q.ntuples > 0
			return true
		end
		
		return false
		
	end
	
	def mark_responded(user, recipient)
		
		return false unless test_goldfish
		
		@con.query("replace into autoresponder_recipients values('%s', '%s', now())" %
			[ @con.escape_string(user), @con.escape_string(recipient) ])
		
	end
	
end
