#
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
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
# http://www.gnu.org/copyleft/gpl.html

package Sendpage::Utilities;

=head1 NAME

Sendpage::Utilities.pm - provides various sendpage-related utilities

=head1 SYNOPSIS

    $str=Sendpage::Modem::HexStr("tab:\t cr:\r");

=head1 DESCRIPTION

This is a module for use in sendpage(1).

=head1 BUGS

This needs more docs.

=cut


# globals

sub HexStr {
        my($self,$text)=@_;

	# Convert non-printable characters into {0xXX}
	$text=~s/([^\040-\176])/sprintf("{0x%02X}",ord($1))/ge
        	if (defined($text));

        return $text || "-undef-";
}

1;

__END__

=head1 AUTHOR

Kees Cook <kees@outflux.net>

=head1 SEE ALSO

perl(1), sendpage(1), Sendpage::KeesConf(3), Sendpage::KeesLog(3), 
Sendpage::PagingCentral(3), Sendpage::PageQueue(3), Sendpage::Page(3),
Sendpage::Recipient(3), Sendpage::Queue(3)

=head1 COPYRIGHT

Copyright 2000-2004 Kees Cook.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

