# engine-config

Usage
./configure_engine.sh [-c] [-a] [-t] [-m] [-l] [-k] [-w] [-d] [-h] <DELPHIX_ENGINE_IP>

	-h: Help (Display this message)
	-c: Configure only.  Skip disk intialization, new passwords, registration, and engine type
	-a: Configure ALL.  Same as "-tmlkw"
	-t: Configure Time
	-m: Configure eMail
	-l: Configure LDAP
	-k: Configure Kerberos
	-w: Configure Web Proxy
	-d: DEBUG.  Print extra info

The script requires one positional argument DELPHIX_ENGINE_IP
The script uses a hardcoded config file called config.cfg.  Place your settings there.
Example:
	./configure_engine.sh 172.16.126.153
	Configures the engine at this IP, using parameters in config.cfg
