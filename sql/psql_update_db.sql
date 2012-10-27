create table domain_admins (
	domain_id integer references virtual_domains(id),	
	user_id integer references virtual_users(id),
	primary key(domain_id, user_id)
);

alter table virtual_users add column super_admin boolean default false;

CREATE TABLE autoresponder (
	email varchar(255) NOT NULL default '' PRIMARY KEY,
	descname varchar(255) default NULL,
	from_date date NOT NULL default '1900-01-01',
	to_date date NOT NULL default '1900-01-01',
	message text NOT NULL,
	enabled integer NOT NULL default '0',
	subject varchar(255) NOT NULL default ''
);

create table autoresponder_recipients (
	user_email varchar(255) not null references autoresponder(email),
	recipient_email varchar(255) not null,
	send_date timestamp not null,
	primary key(user_email, recipient_email)
);
