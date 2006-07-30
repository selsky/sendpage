package Sendpage::Db;

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
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
# <URL:http://www.gnu.org/copyleft/gpl.html>

use 5.6.1;			# To be safe; using lvaluable subs
use strict;			# Avoid MetaGoof #1
use warnings;			# Avoid MetaGoof #2

use DBI;
use Carp;			# A great way to misdirect blame ;)

=head1 NAME

Sendpage::Db - encapsulates the data of a single recipient

=head1 SYNOPSIS

 $db = Sendpage::Db->new($dsn);
 $db->setdb($dsn, $user, $pass, $table);
 $db->check("$name:$type");
 $db->update("$name:$type", "$value");
 $db->delete("$name:$type");

=head1 DESCRIPTION

This is a module is used internally by L<sendpage> for encapsulating
data for a single recipient in an object-oriented interface.

The available methods are:

=cut

=over 4

=item new LIST

Instantiates a new Sendpage::Db object.

=cut

sub new
{
    my ($class, $dsn, $user, $pass, $table) = @_;
    my $self = { };		# to be taken of care by setdb()
    bless $self => $class;

    return undef unless setdb($self, $dsn, $user, $pass, $table);
    return $self;
}

# automagically create accessor methods; we set them with the
# `lvalue' attribute (available in Perl 5.6) so we can do attribute
# manipulations like in C++, e.g. `$db->table = "sendpage"'
foreach my $field (qw(dbh dsn user pass table)) {
    no strict "refs";		# access symbol table
    *$field = sub : lvalue
    {
	my $self = shift;
	$self->{uc $field} = shift if (@_);
	$self->{uc $field};	# no need for `return'
    };
}

=item setdb LIST

Prepares the core attributes for a Sendpage::Db object.

Normally called within a C<new> invocation, C<setdb> accepts the
dsn, username, password, and table to be used in the database.

Emits the return value of C<connect> (0 if successful, 1 otherwise.)

=cut

sub setdb
{
    my ($self, $dsn, $user, $pass, $table) = @_;

    $self->table = $table || "sendpage";
    $self->dsn = $dsn;
    if ($user) {
	$self->user = $user;
	if ($pass) {
	    $self->pass = $pass;
	} else {
	    if ($self->pass) {
		$self->pass = undef;
	    }
	}
    } else {
	if ($self->user) {
	    $self->user = undef;
	}
    }

    return $self->connect;
}

=item connect()

Make a connection from the Sendpage::Db object to the underlying
database using DBI.

Accepts a Sendpage::Db object.

Emits 0 if successful, 1 otherwise.

=cut

sub connect
{
    my $self = shift;

    my ($dsn, $user, $pass, $table, $rv);

    $dsn = $self->dsn;
    $user = $self->user if $self->user;
    $pass = $self->pass if $self->pass;
    $table = $self->table;
    $rv = 0;

    if ($self->dbh) {
	my $dbh = $self->dbh;
	$dbh->disconnect;
    }

    # Then again, DBI has its own `connect' method, so...
    if ($self->dbh = DBI->connect($dsn, $user, $pass)) {
	return 0;
    } else {
	printf STDERR carp("DB connection to $dsn failed!\n");
	return 1;
    }
}

=item check KEY

Check if a given key is defined in the table.

=cut

sub check
{
    my ($self, $key) = @_;
    my $result;

    my ($sth, $table, $query, @result);

    $key = $self->quote($key);

    $table = $self->table;
    $query = "select v from $table where k = $key";

    $sth = $self->query($query);

    return @result unless ($sth || $sth->rows > 0);
    $result = $sth->fetchrow_array;
    if ($result =~ m/[\s,]/) {
	my @parts = split /[\s,]+/ => $result;
	foreach my $item (@parts) {
	    # drop white space
	    $item =~ s/^\s*//;
	    $item =~ s/\s*$//;
	    push @result, $item;
	}
    } else {
	@result = ($result);
    }

    return @result;
}

=item show()

Show keys and their corresponding values from the table.

=cut

sub show
{
    my $self = shift;
    my ($sth, $key, $table, $query);

    $table = $self->table;
    $query = "select k,v from $table";

    $sth = $self->query($query);
    return undef unless $sth;

	while (my ($key, $val) = $sth->fetchrow_array) {
        print "$key\t=\t$val\n"
    }
    $sth->finish;
    return 0;
}

=item update KEY, VALUE

Updates a table's key with the given value.

=cut

sub update
{
    my ($self, $key, $val) = @_;
    my ($sth, $table, $query, $rv);

    $table = $self->table;

    $key = $self->quote($key);
    $val = $self->quote($val);

    $query = "select k,v from $table where k = $key";
    $sth = $self->query($query);
    return undef unless $sth;

    $sth->finish;
    if ($sth->rows > 0) {
	$query = "update $table set v = $val where k = $key";
	$sth = $self->query($query);
    } else {
	$query = "insert into $table values ($key, $val)";
	$sth = $self->query($query);
    }
    return undef unless $sth;
    $sth->finish;
    return 0;
}

=item delete KEY

Deletes a key (and its value) in the table.

=cut

sub delete
{
    my ($self, $key) = @_;

    my ($sth, $table, $query);
    $table = $self->table;

    $key = $self->quote($key);
    $query = "delete from $table where k = $key";
    $sth = $self->query($query);
    return undef unless $sth;
    $sth->finish;
    return 0;
}

=back

=for developers
Add other core functions here; the next set describes helper
functions...

=cut

# Now for some db helper functions, not called by external
# modules...  We could probably enforce some caller() check here, to
# be really sure these subroutines aren't called from the outside...

sub prepare
{
    my ($self, $query) = @_;

    return $self->dbh->prepare($query);
}

sub quote
{
    my ($self, $string) = @_;

    return $self->dbh->quote($string);
}

sub query
{
    my ($self, $query) = @_;

    my ($sth, $rv);

    #warn "preparing [$query]\n";
    $sth = $self->prepare($query);

    unless ($rv = $sth->execute) {
	printf STDERR carp("[$query] failed, returned $rv\n");
	return undef;
    }

    $rv = $sth->rows;

    if ($rv < 0) {
	$sth->finish;
	printf STDERR carp("[$query] returned $rv rows\n");
	return undef;
    }

    return $sth;
}

1;				# This is a module

__END__

=head1 AUTHOR

Todd T. Fries <todd@fries.net>

=head1 BUGS

Need to write more docs; now in progress.

=head1 SEE ALSO

Man pages: L<perl>, L<sendpage>.

Module documentation: L<Sendpage::KeesConf>, L<Sendpage::KeesLog>,
L<Sendpage::Modem>, L<Sendpage::PagingCentral>, L<Sendpage::PageQueue>,
L<Sendpage::Page>, L<Sendpage::Queue>

=head1 COPYRIGHT

Copyright 2004 Todd T. Fries.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
