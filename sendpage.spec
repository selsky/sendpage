#
# This spec file was originally generated by cpan2rpm v2.019
# For more information please visit: http://perl.arix.com/
#
%define pkgname sendpage
%define filelist %{pkgname}-%{version}-filelist
%define maketest 1
# Be sure to change both
%define pkgversion 1
%define rpmversion 1.0.0
%define namever %{pkgname}-%{pkgversion}

name:		perl-sendpage
summary:	sendpage - listen for pages via SNPP, and send pages via modem
epoch:		1
version:	%{rpmversion}
release:	1
vendor:		Kees Cook <kees@outflux.net>
packager:	Arix International <cpan2rpm@arix.com>
license:	Artistic
group:		Applications/CPAN
url:		http://sendpage.org/
buildroot:	%{_tmppath}/%{name}-%{version}-%(id -u -n)
buildarch:	noarch
source:		%{namever}.tar.gz
%description
sendpage sends alphanumeric pages via TAP or UCP over a modem.
#
# This package was originally generated with the cpan2rpm
# utility.  To get this software or for more information
# please visit: http://perl.arix.com/
#
%prep
%setup -q -n %{namever}
chmod -R u+w %{_builddir}/%{namever}
%build
CFLAGS="$RPM_OPT_FLAGS"
%{__perl} Makefile.PL `%{__perl} -MExtUtils::MakeMaker -e ' print qq|PREFIX=%{buildroot}%{_prefix}| if \$ExtUtils::MakeMaker::VERSION =~ /5\.9[1-6]|6\.0[0-5]/ '`
%{__make} 
%if %maketest
%{__make} test
%endif
%install
[ "%{buildroot}" != "/" ] && rm -rf %{buildroot}
%{makeinstall} `%{__perl} -MExtUtils::MakeMaker -e ' print \$ExtUtils::MakeMaker::VERSION <= 6.05 ? qq|PREFIX=%{buildroot}%{_prefix}| : qq|DESTDIR=%{buildroot}| '`
[ -x /usr/lib/rpm/brp-compress ] && /usr/lib/rpm/brp-compress
# SuSE Linux
if [ -e /etc/SuSE-release ]; then
%{__mkdir_p} %{buildroot}/var/adm/perl-modules
%{__cat} `find %{buildroot} -name "perllocal.pod"`  \
| %{__sed} -e s+%{buildroot}++g                 \
> %{buildroot}/var/adm/perl-modules/%{name}
fi
# remove special files
find %{buildroot} -name "perllocal.pod" \
-o -name ".packlist"                \
-o -name "*.bs"                     \
|xargs -i rm -f {}
# no empty directories
find %{buildroot}%{_prefix}             \
-type d -depth                      \
-exec rmdir {} \; 2>/dev/null
%{__perl} -MFile::Find -le '
find({ wanted => \&wanted, no_chdir => 1}, "%{buildroot}");
print "%defattr(-,root,root)";
print "%doc  Changes README LICENSE docs TODO";
for my $x (sort @dirs, @files) {
push @ret, $x unless indirs($x);
}
print join "\n", sort @ret;
sub wanted {
return if /auto$/;
local $_ = $File::Find::name;
my $f = $_; s|^%{buildroot}||;
return unless length;
return $files[@files] = $_ if -f $f;
$d = $_;
/\Q$d\E/ && return for reverse sort @INC;
$d =~ /\Q$_\E/ && return
for qw|/etc %_prefix/man %_prefix/bin %_prefix/share|;
$dirs[@dirs] = $_;
}
sub indirs {
my $x = shift;
$x =~ /^\Q$_\E\// && $x ne $_ && return 1 for @dirs;
}
' > %filelist
[ -z %filelist ] && {
echo "ERROR: empty %files listing"
exit -1
}
grep -rsl '^#!.*perl'  Changes README LICENSE docs TODO debian |
grep -v '.bak$' |xargs --no-run-if-empty \
%__perl -MExtUtils::MakeMaker -e 'MY->fixin(@ARGV)'
%clean
[ "%{buildroot}" != "/" ] && rm -rf %{buildroot}
%files -f %filelist
%changelog
* Fri Jan 16 2004 root@octopus.pdx.osdl.net
- Initial build.
