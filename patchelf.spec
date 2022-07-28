Summary: A utility for patching ELF binaries

Name: patchelf
Version: @PACKAGE_VERSION@
Release: @RPM_RELEASE@%{?dist}
Epoch: 1
License: GPL
Group: Development/Tools
URL: http://nixos.org/patchelf.html
Source0: %{name}-%{version}.tar.gz
Patch0: increase_size_to_work_with_debug_binaries.patch
BuildRoot: %{_tmppath}/%{name}-%{version}-buildroot
Prefix: /usr

%description

PatchELF is a simple utility for modifing existing ELF executables and
libraries.  It can change the dynamic loader ("ELF interpreter") of
executables and change the RPATH of executables and libraries.

%prep
%setup -q
%patch0 -p1

%build
%if 0%{?rhel} == 6
    sed -i "s: serial-tests::g" configure.ac
%endif
./bootstrap.sh
./configure --prefix=%{_prefix}
make
make check

%install
rm -rf $RPM_BUILD_ROOT
make DESTDIR=$RPM_BUILD_ROOT install
# rpmbuild automatically strips... strip $RPM_BUILD_ROOT/%%{_bindir}/* || true

%clean
rm -rf $RPM_BUILD_ROOT

%files
%{_bindir}/patchelf
%doc %{_docdir}/patchelf/README.md
%{_mandir}/man1/patchelf.1.gz

%changelog
* Wed May 27 2020 Illia Pshonkin <illia.pshonkin@percona.com>
- Packaging for 0.10
