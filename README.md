Proclaunch is a super simple pure-perl user space process manager. It starts your processes and keeps them running. It's comparable to [runit][], except it manages processes that know how to daemonize themselves. It's also only a few hundred lines of simple perl with minimal dependencies. 

### Installation

    $ git clone git://github.com/peterkeen/proclaunch.git
    $ cd proclaunch
    $ perl Build.PL
    $ ./Build install

### Usage

    $ proclaunch [state directory] [profile directory]

When executed, proclaunch will daemonize itself and write it's pid file to `$state_directory/proclaunch.pid`.

The profile directory should contain a series of directories, each of which describes a process to be managed via a set of specially named files:    

* `pid_file`
    contains the path to the file where run will place it's pid

* `run`
    is an executable script that will daemonize itself and write it's pid to the path in pid_file

* `restart`
    is an optional empty file who's presence tells proclaunch to restart `run` if it dies.
    
* `user`
    is an optional file containing the user name that should execute `run`. Only effective if proclaunch has been run as root.
    
### Behavior

Initially, proclaunch will launch all profiles contained in the profile directory. When a profile exits and the `restart` file exists, the profile will be restarted. Additionally, proclaunch will scan every five seconds to see if either an individual profile directory has changed, been added, or disappeared. Added profiles will be started, removed profiles will be stopped with SIGTERM, and changed profiles will be restarted. Proclaunch will also check the inode and mtime on the profiles directory has a whole every second and rescan immediately if it has changed.

[runit]:           http://smarden.org/runit/
