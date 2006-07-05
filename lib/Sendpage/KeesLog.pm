package Sendpage::KeesLog;

# KeesLog.pm implements a logging subsystem involving syslog and/or stderr
#
# $Id$
#
# Copyright (C) 2000-2004 Kees Cook
# kees@outflux.net, http://outflux.net/
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
# <URL:http://www.gnu.org/copyleft/gpl.html>

use Sys::Syslog qw(:DEFAULT setlogsock);

=head1 NAME

Sendpage::KeesLog - implements a logging subsystem

=head1 SYNOPSIS

 $log = Sendpage::KeesLog->new();
 $log->on();
 $log->do('crit',"Something bad happened");
 $log->reconfig($config);
 $log->do('debug',"I'm doing things");
 $log->off();
 $log->do('info',"Look at me, I'm writing to stderr now");

=head1 DESCRIPTION

This module is used by L<sendpage> for its logging.

=head1 BUGS

I need to write more docs for it.

=cut

my %LogLevels = (
		 debug   => 0,
		 info    => 1,
		 notice  => 2,
		 warning => 3,
		 err     => 4,
		 crit    => 5,
		 alert   => 6,
		 emerg   => 7,
		);

# FIXME: can I have this thing detect if STDERR has already been closed and
#	kick and scream some other way?

# takes parameters "Syslog" (1 or 0), "Opts", "Facility", "MinLevel"
sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = { };

    bless $self => $class;

    $self->reconfig(@_);

    return $self;
}

# restarts logging with config'd values
sub reconfig
{
    my $self = shift;
    my %arg  = @_;

    $self->{SYSLOG}   = $arg{Syslog};
    $self->{OPTS}     = $arg{Opts};
    $self->{FACILITY} = $arg{Facility};
    $self->{MINLEVEL} = $arg{MinLevel};
    $self->{MINLEVEL} = "debug" unless (defined $LogLevels{$self->{MINLEVEL}});

    unless (defined $self->{SYSLOG}) {
	$self->{SYSLOG} = 0;
	$self->off();
    } else {
	$self->on() if (defined $self->{OPEN});
    }
}

sub off
{
    my $self = shift;

    if (defined $self->{OPEN}) {
	closelog;
	undef $self->{OPEN};
    }
}

sub on
{
    my $self = shift;

    $self->off();
    if ($self->{SYSLOG} == 1) {
	# Comment out the following line if Solaris complains about
	# syslog.
	setlogsock('inet') unless defined setlogsock('unix');
	my $ret = openlog "sendpage", $self->{OPTS}, $self->{FACILITY};
	$self->{OPEN} = 1;
    }
}

# perform a logging function
sub do
{
    my($self, $pri, $format, @args) = @_;

    $pri = $self->{MINLEVEL}
	if ($LogLevels{$pri} < $LogLevels{$self->{MINLEVEL}});

    # convert tabs since syslog doesn't like them
    $format =~ s/\t/     /g;

    # question is: who adds the "\n"?  Me or syslog?  I assume me now.
    unless (defined $self->{OPEN}) {
	my $str = sprintf("%s [$$ $pri]: $format",
			  scalar(localtime()), @args);
	warn $str . "\n";
    } else {
	# FIXME: shouldn't I check error codes?
	syslog($pri, $format, @args);
    }
}

sub DESTROY
{
    my ($self) = @_;

    $self->off();
}

1;				# This is a module

__END__

=head1 AUTHOR

Kees Cook <kees@outflux.net>

=head1 SEE ALSO

Man pages: L<perl>, L<sendpage>.

Module documentation: L<Sendpage::KeesConf>, L<Sendpage::Modem>,
L<Sendpage::PagingCentral>, L<Sendpage::PageQueue>, L<Sendpage::Page>,
L<Sendpage::Recipient>, L<Sendpage::Queue>.

=head1 COPYRIGHT

Copyright 2000 Kees Cook.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
