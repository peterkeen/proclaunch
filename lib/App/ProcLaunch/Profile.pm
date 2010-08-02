package App::ProcLaunch::Profile;

use POSIX qw/ :sys_wait_h /;

use App::ProcLaunch::Util qw/
    read_file
    still_running
    cleanup_dead_pid_file
/;

use File::Stat;

use Class::Struct
    directory => '$',
    _pid_file => '$',
    dir_stat  => '$'
;

sub run {
    my $self = shift;
    return unless cleanup_dead_pid_file($self->pid_file());
    warn "Starting " . $self->directory();

    my $stat = stat($self->directory());
    $self->dir_stat($stat);

    defined(my $pid = fork()) or die "Could not fork: $!";

    if ($pid == 0) {
        $self->drop_privs();
        chdir $self->directory();
        exec("./run");
    } else {
        waitpid($pid, 0);
    }
}

sub drop_privs
{
    # TODO
}

sub pid_file_exists {
    my $self = shift;
    return -e $self->pid_file();
}

sub current_pid {
    my $self = shift;
    return $self->pid_file_exists() ? read_file($self->pid_file()) : undef;
}

sub is_running {
    my $self = shift;
    my $pid = $self->current_pid();
    return still_running($self->pid_file());
}

sub should_restart {
    my $self = shift;
    return -e $self->profile_file('restart');
}

sub profile_file {
    my ($self, $filename) = @_;
    return join("/", $self->directory(), $filename);
}

sub pid_file {
    my $self = shift;
    unless ($self->_pid_file()) {
        my $profile_pid_file = $self->profile_file('pid_file');
        die "No file named pid_file for profile " . $self->directory() unless -e $profile_pid_file;
        my $pid_file = read_file($profile_pid_file);
        $pid_file =~ s/\s*$//;
        $self->_pid_file($pid_file);
    }
    return $self->_pid_file();
}

sub send_signal
{
    my ($self, $signal) = @_;
    if ($self->is_running()) {
        kill $signal, $self->current_pid();
    }
}

sub has_changed
{
    warn "here";
    my $self = shift;
    my $stat = stat($self->directory());

    warn "checking " . $self->dir_stat()->mtime() . " against " . $stat->mtime();

    return $self->dir_stat()->ino() ne $stat->ino() || $self->dir_stat()->mtime() ne $stat->mtime();
}

1;
