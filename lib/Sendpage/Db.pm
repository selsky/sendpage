#
# this package will access databases for looking up recipients
#
# $Id$
#
# Copyright (C) 2004 Todd Fries
# todd@fries.net, http://FreeDaemonConsulting.com/
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

package Sendpage::Db;

use DBI;
use Carp;
#use strict;

=head1 NAME

Db.pm - encapsulates the data of a single recipient

=head1 SYNOPSIS

    $db = Sendpage::Db->new($dsn);
    $db->setdb($dsn, $user, $pass, $table);
    $db->check("$name:$type");
    $db->update("$name:$type","$value");
    $db->delete("$name:$type");

=head1 DESCRIPTION

This is a module for use in sendpage(1).

=head1 BUGS

Need to write more docs.

=cut


sub new {
	my ($class, $dsn, $user, $pass, $table) = @_;
        my ($self)  = {};

        bless $self, $class;

	if ( setdb($self, $dsn, $user, $pass, $table) ) {
		return undef;
	}
	return $self;
}

sub setdb {
	my ($self, $dsn, $user, $pass, $table) = @_;
	my ($rv);
	$self->{TABLE} = $table || "sendpage";
	$self->{DSN} = $dsn;
	if ($user) {
		$self->{USER} = $user;
		if ($pass) {
			$self->{PASS} = $pass;
		} else {
			if ($self->{PASS}) {
				$self->{PASS} = undef;
			}
		}
	} else {
		if ($self->{USER}) {
			$self->{USER} = undef;
		}
	}

	return $self->connect;
}

sub connect {
	my ($self) = @_;

	my ($dsn, $user, $pass, $table, $rv);

	$dsn = $self->{DSN};
	$user = $self->{USER} if $self->{USER};
	$pass = $self->{PASS} if $self->{PASS};
	$table = $self->{TABLE};
	$rv = 0;

	if ($self->{DBH}) {
		$self->{DBH}->disconnect;
	}

	if ($self->{DBH} = DBI->connect($dsn, $user, $pass)) {
		return 0;
	} else {
		printf STDERR carp("DB connection to $dsn failed!\n");
		return 1;
	}
}

sub check {
	my ($self, $key) = @_;
	my ($result);

	my ($sth, $table, $query, @result);

	$key = $self->quote($key);

	$table = $self->{TABLE};
	$query = "select v from $table where k = $key";

	$sth = $self->query($query);

	if (! $sth || $sth->rows < 1) {
		return (@result);
	}
	$result = $sth->fetchrow_array;
	if ($result =~ m/[\s,]/) {
		my @parts = split(/[\s,]+/,$result);
		my $item;
		foreach $item (@parts) {
			# drop white space
			$item=~s/^\s*//;
			$item=~s/\s*$//;
			push(@result,$item);
		}
	} else {
		@result = ($result);
	}

	return (@result);
}

sub show {
	my ($self) = @_;
	my ($sth,$key,$table,$query);

	$table = $self->{TABLE};
	$query = "select k,v from $table";

	$sth = $self->query($query);
	if (! $sth) {
		return undef;
	}

	while (($key,$val) = $sth->fetchrow_array) {
		print "$key\t=\t$val\n";
	}
	$sth->finish;
	return 0;
}

sub update {
	my ($self,$key,$val) = @_;
	my ($sth,$table,$query,$rv);

	$table = $self->{TABLE};

	$key = $self->quote($key);
	$val = $self->quote($val);

	$query = "select k,v from $table where k = $key";
	$sth = $self->query($query);
	if (! $sth) {
		return undef;
	}

	$sth->finish;
	if ($sth->rows > 0) {
		$query = "update $table set v = $val where k = $key";
		$sth = $self->query($query);
	} else {
		$query = "insert into $table values ($key,$val)";
		$sth = $self->query($query);
	}
	if (! $sth) {
		return undef;
	}
	$sth->finish;
	return 0;
}

sub delete {
	my ($self,$key) = @_;

	my ($sth, $table, $query);
	$table = $self->{TABLE};

	$key = $self->quote($key);
	$query = "delete from $table where k = $key";
	$sth = $self->query($query);
	if (! $sth) {
		return undef;
	}
	$sth->finish;
	return 0;
}

# Now for some db helper functions, not called by external modules

sub prepare {
	my ($self, $query) = @_;

	return $self->{DBH}->prepare($query);
}

sub quote {
	my ($self, $string) = @_;

	return $self->{DBH}->quote($string);
}

sub query {
	my ($self, $query) = @_;

	my ($sth, $rv);

	#warn "preparing [$query]\n";
	$sth = $self->prepare($query);

	if (! ($rv = $sth->execute) ) {
		printf STDERR carp("[$query] failed, returned $rv\n");
		return undef;
	}

	$rv = $sth->rows;

	if ( $rv < 0 ) {
		$sth->finish;

		printf STDERR carp("[$query] returned $rv rows\n");

		return undef;
	}

	return $sth;
}

1;

__END__

=head1 AUTHOR

Todd T. Fries <todd@fries.net>

=head1 SEE ALSO

perl(1), sendpage(1), Sendpage::KeesConf(3), Sendpage::KeesLog(3),
Sendpage::Modem(3), Sendpage::PagingCentral(3), Sendpage::PageQueue(3),
Sendpage::Page(3), Sendpage::Queue(3)

=head1 COPYRIGHT

Copyright 2004 Todd T. Fries.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

