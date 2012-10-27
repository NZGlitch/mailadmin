#!/usr/bin/env ruby

module MailConfig
	DB_TYPE = "pg"		#pg or mysql
	DB_HOST = "localhost"
	DB_USER = "mailuser"
	DB_PASS = "mailuser"
	DB_DB = "mailserver"
	
# If you're going to use the built-in autoresponder, this should return a
# user's maildir mailbox when %u is replaced with their username, and %d with
# the domain
	AR_MAILDIR = "/var/mail/vhosts/%d/%u"
	AR_SERVER = "localhost"
	
end
