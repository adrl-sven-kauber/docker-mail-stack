<?php
// Settings on top of the image's config (hosts and plugins come from compose.yaml).
$config['product_name'] = getenv('WEBMAIL_TITLE') ?: 'Webmail';
$config['skin'] = 'elastic';

// Behind the host's nginx (TLS ends there): trust its X-Forwarded-For.
$config['use_https'] = true;
$config['proxy_whitelist'] = [getenv('PROXY_IP') ?: '172.21.0.1'];

// Security
$config['login_rate_limit'] = 3;          // failed logins per minute per client
$config['session_lifetime'] = 60;         // minutes
$config['ip_check'] = true;
$config['x_frame_options'] = 'deny';
$config['cipher_method'] = 'AES-256-CBC';

// Sieve filters and vacation replies (DMS ENABLE_MANAGESIEVE=1, internal port 4190)
$config['managesieve_host'] = 'tls://' . getenv('MAIL_HOSTNAME');
$config['managesieve_port'] = 4190;
$config['managesieve_vacation'] = 1;

// Mailboxes
$config['junk_mbox'] = 'Junk';
$config['markasjunk_learning_driver'] = null;   // DMS (RSPAMD_LEARN) learns on move to/from Junk
$config['archive_mbox'] = 'Archive';
$config['draft_autosave'] = 60;
$config['mail_pagesize'] = 100;
$config['date_format'] = 'Y-m-d';
$config['time_format'] = 'H:i';
