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
%define maketest 0
# Install bits
%define user sendpage
%define spool /var/spool/sendpage

name:		sendpage
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
Sendpage is designed to speak SNPP on one end and TAP (or UCP) on the
other.  It gets pages from the network via SNPP, and then uses a modem
or a direct serial connection to deliver the pages to a Paging Central
(or "paging terminal").  Sendpage requires, for modem use, that you know
your PC's access number (which is not usually advertised by your paging
provider), and you need to know the PINs of the pagers you want to deliver
pages to.  All of this information is known by your paging provider.
If you ARE a paging provider, your job is much easier.  ;)
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
%{__perl} Makefile.PL DESTDIR=%{buildroot} `%{__perl} -MExtUtils::MakeMaker -e ' print qq|PREFIX=%{buildroot}%{_prefix}| if \$ExtUtils::MakeMaker::VERSION =~ /5\.9[1-6]|6\.0[0-5]/ '`
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
	print "%doc    Changes README FEATURES LICENSE THANKS TODO modemtest docs";
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

# Install config files
%{__mkdir_p} %{buildroot}/etc
for i in email2page.conf sendpage.cf snpp.conf;
do
	%{__install} -m 644 $i %{buildroot}/etc/$i
	echo "%config /etc/$i" >> %filelist
done

# Create spool
%{__mkdir_p} %{buildroot}%{spool}
echo "%attr(0770,%{user},root) %{spool}" >> %filelist

# Write init file
%{__mkdir_p} %{buildroot}/etc/init.d
%{__install} -m 755 sendpage.init %{buildroot}/etc/init.d/sendpage
echo "%config /etc/init.d/sendpage" >> %filelist

# Set up system permission defaults
GROUP_LOCK=`ls -ld /var/lock | awk '{print $4}'`
GROUP_TTY=`ls -ld /dev/ttyS0 | awk '{print $4}'`
if [ ! -z $GROUP_LOCK ]; then
	%{__perl} -pi -e "s/^#group-lock.*/group-lock=$GROUP_LOCK/;" %{buildroot}/etc/sendpage.cf
fi
if [ ! -z $GROUP_TTY ]; then
	%{__perl} -pi -e "s/^#group-tty.*/group-tty=$GROUP_TTY/;" %{buildroot}/etc/sendpage.cf
fi

#cat %filelist
[ -z %filelist ] && {
	echo "ERROR: empty %files listing"
	exit -1
}
grep -rsl '^#!.*perl'  Changes README FEATURES LICENSE THANKS TODO modemtest docs debian |
	grep -v '.bak$' |xargs --no-run-if-empty \
	%__perl -MExtUtils::MakeMaker -e 'MY->fixin(@ARGV)'

%clean
[ "%{buildroot}" != "/" ] && rm -rf %{buildroot}

# Add the user and group
%pre
id %{user} >/dev/null 2>&1 || \
	/usr/sbin/useradd -c 'Sendpage System' -d %{spool} -r -M %{user}

%post
if [ $1 = 1 ]; then
    /sbin/chkconfig --add %{name}
fi

%preun
if [ $1 = 0 ]; then
    /sbin/chkconfig --del %{name}
fi

%postun
if [ $1 -ge 1 ]; then
    /sbin/chkconfig %{name} && /sbin/service %{name} restart >/dev/null 2>&1
fi

%files -f %filelist

%changelog
* Fri May 07 2004 kees@outflux.net
- Tweaking for actual use :)
* Fri Jan 16 2004 kees@outflux.net
- Initial build.
