package Sendpage::Utilities;

# Utilities.pm provides various sendpage-related utilities
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

=head1 NAME

Sendpage::Utilities - provides various sendpage-related utilities

=head1 SYNOPSIS

 $str = Sendpage::Modem::HexStr("tab:\t cr:\r");

=head1 DESCRIPTION

This module is used internally by L<sendpage> as a repository of other
utility functions for various purposes.

Currently it implements only one (unexported) function, C<HexStr>.

=cut

# globals

=head2 Methods

=over 4

=item HexStr EXPR

Convert non-printable characters in a string generated from EXPR into a
readable format (currently C<{0xXX}>).

=cut

sub HexStr
{
    my ($self, $text) = @_;

    # Convert non-printable characters into {0xXX}
    $text =~ s/([^\040-\176])/sprintf("{0x%02X}",ord($1))/ge
	if defined $text;

    return $text || "-undef-";
}

=for developers: add new functions here.

=back

=cut

1;				# This is a module

__END__

=head1 AUTHOR

Kees Cook <kees@outflux.net>

=head1 BUGS

This needs more docs.

=head1 SEE ALSO

Man pages: L<perl>, L<sendpage>.

Module documentation: L<Sendpage::KeesConf>, L<Sendpage::KeesLog>,
L<Sendpage::PagingCentral>, L<Sendpage::PageQueue>, L<Sendpage::Page>,
L<Sendpage::Recipient>, L<Sendpage::Queue>.

=head1 COPYRIGHT

Copyright 2000-2004 Kees Cook.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
