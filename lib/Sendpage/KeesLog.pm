#
# KeesLog.pm implements a logging subsystem involving syslog and/or stderr
#
# $Id$
#
# Copyright (C) 2000 Cornelius Cook
# cook@cpoint.net, http://collective.cpoint.net/
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
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
# http://www.gnu.org/copyleft/gpl.html

package Sendpage::KeesLog;
use Sys::Syslog qw(:DEFAULT setlogsock);

=head1 NAME

Sendpage::KeesLog - implements a logging subsystem

=head1 SYNOPSIS

    $log=Sendpage::KeesLog->new();
    $log->on();
    $log->do('crit',"Something bad happened");
    $log->reconfig($config);
    $log->do('debug',"I'm doing things");
    $log->off();
    $log->do('info',"Look at me, I'm writing to stderr now");

=head1 DESCRIPTION

This module is used in sendpage(1).

=head1 BUGS

I need to write more docs for it.

=cut


# FIXME: can I have this thing detect if STDERR has already been closed and
#	kick and scream some other way?

# takes parameters "Syslog" (1 or 0), "Opts", "Facility"
sub new {
        my $proto = shift;
        my $class = ref($proto) || $proto;
        my $self  = {};

        bless($self,$class);

	$self->reconfig(@_);

        return $self;
}

# restarts logging with config'd values
sub reconfig {
	my $self = shift;
	my %arg = @_;

	$self->{SYSLOG} = $arg{Syslog};
	$self->{OPTS}   = $arg{Opts};
	$self->{FACILITY}=$arg{Facility};

	if (!defined($self->{SYSLOG})) {
		$self->{SYSLOG}=0;
		$self->off();
	}
	else {
		$self->on() if (defined($self->{OPEN}));
	}
}

sub off {
	my $self=shift;

	if (defined($self->{OPEN})) {
		closelog;
		undef $self->{OPEN};
	}	
}

sub on {
	my $self=shift;

	$self->off();
	if ($self->{SYSLOG}==1) {
		# Comment out the following three lines if Solaris complains
		# about syslog.
		if (!defined(setlogsock('unix'))) {
			setlogsock('inet');
		}
		my $ret=openlog "sendpage",
				$self->{OPTS},
				$self->{FACILITY};
		$self->{OPEN}=1;
	}
}

# perform a logging function
sub do {
	my($self,$pri,$format,@args)=@_;

	# convert tabs since syslog doesn't like them
	$format=~s/\t/     /g;

	# question is: who adds the "\n"?  Me or syslog?  I assume me now.
	if (!defined($self->{OPEN})) {
		my $str=sprintf("($$: $pri) $format",@args);
		warn $str."\n";
	}
	else {
		# FIXME: shouldn't I check error codes?
		syslog($pri,$format,@args);
	}
}

sub DESTROY {
	my($self)=@_;

	$self->off();
}

1;

__END__

=head1 AUTHOR

Kees Cook <cook@cpoint.net>

=head1 SEE ALSO

perl(1), sendpage(1), Sendpage::KeesConf(3), Sendpage::Modem(3),
Sendpage::PagingCentral(3), Sendpage::PageQueue(3), Sendpage::Page(3),
Sendpage::Recipient(3), Sendpage::Queue(3)

=head1 COPYRIGHT

Copyright 2000 Kees Cook.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

