@include "json.awk"

# Save email addresses
BEGIN {
	json_load("var/mail.json", mail_enable)
	for (_user in mail_enable)
		debug("watching " mail_enable[_user] " for " _user)
}

TO == NICK && /^sync/ {
	json_load("var/mail.json", mail_enable)
	for (_user in mail_enable)
		debug("watching " mail_enable[_user] " for " _user)
}

# Email notifications
BEGIN {
	mail_hist   = 5*60 # If the users has not spoken withn mail_before before
	mail_before = 5*60 # someone mentions their name and does not reply within
	mail_after  = 5*60 # mail_after seconds, email them hist seconds of the backlog
}

function mail_send(addr, subj, body,
		   from, error, sendmail, errmsg)
{
	from  = NICK "<" NICK "@pileus.org>"
	error = "If you received this message in error,\n" \
	        "someone in #rhnoise is being a jerk"

	gsub(/[^a-zA-Z0-9_+@.-]/, "", addr)
	sendmail = "/usr/sbin/sendmail " addr
	print "To: " addr      | sendmail
	print "From: " from    | sendmail
	print "Subject: " subj | sendmail
	print ""               | sendmail
	print body             | sendmail
	print ""               | sendmail
	print error            | sendmail
	close(sendmail)
}

function mail_prep(user, chan,
		   addr, line, body,
		   sec, si, sn, ss,
		   msg, mi, mn)
{
	addr = mail_enable[user]
	sn   = asorti(mail_log[chan], ss)
	body = ""
	for (si = 1; si <= sn; si++) {
		sec = ss[si]
		mn = length(mail_log[chan][sec])
		for (mi = 0; mi < mn; mi++) {
			msg = mail_log[chan][sec][mi]
			if (sec > mail_ready[user][chan] - mail_hist) {
				if (msg ~ user)
					line = "* " msg
				else
					line = "  " msg
				body = body line "\n"
			}
		}
	}
	say(chan, "notifying " user " at " addr)
	mail_send(addr, "Message for " user " in " chan, body)
	delete mail_ready[user][chan]
}

function mail_run(  user, chan, ready, time)
{
	for (user in mail_ready)
	for (chan in mail_ready[user]) {
		ready = mail_ready[user][chan]
		delay = systime() - ready
		if (ready && delay > mail_after)
			mail_prep(user, chan)
	}
}

function mail_save(file)
{
	json_save(file, mail_enable)
}

# Help
/^\.help$/ {
	say(".help mail -- manage email subscriptions")
}

/^\.help e?mail$/ {
	say("Mail -- email users when they are mentioned")
	say(NICK ": subscribe [addr] -- set your mailing address to [addr]")
	say(NICK ": unsubscribe [addr] -- remove your subscription")
	say(NICK ": addresses -- show your subscription address")
	next
}

# Commands
AUTH == OWNER &&
TO == NICK &&
/^subscribe .* .*/ {
	reply("notifying " $2 " for " $3)
	mail_enable[$3] = $2
	mail_save("var/mail.json")
}

TO == NICK &&
/^subscribe  *[^ ]*$/ {
	_user = FROM
	_addr = $2
	gsub(/[^a-zA-Z0-9_+@.-]/, "", _user)
	gsub(/[^a-zA-Z0-9_+@.-]/, "", _addr)
	reply("notifying " _addr " for " _user)
	mail_enable[_user] = _addr
	mail_save("var/mail.json")
}

AUTH == OWNER &&
TO == NICK &&
/^unsubscribe .*/ {
	reply("well fine then")
	delete mail_enable[$2]
	delete mail_ready[$2]
	delete mail_seen[$2]
	mail_save("var/mail.json")
}

TO == NICK &&
/^unsubscribe$/ {
	reply("well fine then")
	delete mail_enable[FROM]
	delete mail_ready[FROM]
	delete mail_seen[FROM]
	mail_save("var/mail.json")
}

TO == NICK &&
/^addresses/ {
	for (_user in mail_enable)
		reply("\"" _user "\" <" mail_enable[_user] ">")
}

# Message logging and monitoring
DST ~ /^#.*/ {
	for (_user in mail_enable) {
		_idle = systime() - mail_seen[_user]
		if ($0 ~ "\\<"_user"\\>" && _idle > mail_before) {
			mail_ready[_user][DST] = systime()
			debug("queueing messages to " DST " for " _user)
		}
	}
}

FROM in mail_enable {
	delete mail_ready[FROM]
	mail_seen[FROM] = systime()
	debug("clearing message for " FROM)
}

DST ~ /^#.*/ {
	_t = systime()
	_i = length(mail_log[DST][_t])
	if (_i==0) delete mail_log[DST][_t]
	mail_log[DST][_t][_i] = DST " " strftime("(%H:%M:%S) ") FROM ": " $0
	#debug("log["DST"]["_t"]["_i"] = "mail_log[DST][_t][_i])
}

// {
	mail_run()
}
