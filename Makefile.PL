use utf8;
use strict;
use warnings;

use ExtUtils::MakeMaker;
use File::ShareDir::Install;

install_share dist => 'stdlib/modules';

my @exe_files = (
	_script_files( 'bin', skip => { 'zuzu' => 1 } ),
	_script_files('stdlib/scripts'),
);

WriteMakefile(
	NAME => 'Zuzu',
	VERSION_FROM => 'lib/Zuzu.pm',
	ABSTRACT_FROM => 'lib/Zuzu.pm',
	AUTHOR => 'Toby Inkster',
	LICENSE => 'perl',
	MIN_PERL_VERSION => '5.014',
	EXE_FILES => \@exe_files,
	PREREQ_PM => {
		'Archive::Zip' => 0,
		'CBOR::Free' => 0,
		'Coro' => 0,
		'DBD::SQLite' => 0,
		'DBI' => 0,
		'Exporter' => 0,
		'FFI::Platypus' => 0,
		'File::Basename' => 0,
		'File::ShareDir' => 0,
		'File::Spec' => 0,
		'FindBin' => 0,
		'Getopt::Long' => 0,
		'HTML::Selector::XPath' => 0,
		'HTTP::CookieJar' => 0,
		'IO::Handle' => 0,
		'IPC::Run' => 0,
		'IPC::Run3' => 0,
		'JSON::MultiValueOrdered' => 0,
		'Moo' => 0,
		'Net::DNS' => 0,
		'Path::Tiny' => 0,
		'Plack' => 0,
		'Pod::Text::Termcap' => 0,
		'Regexp::Util' => 0,
		'Term::ReadLine::Perl' => 0,
		'Text::CSV_XS' => 0,
		'Types::Serialiser' => 0,
		'URI' => 0,
		'URI::Escape' => 0,
		'Unicode::Normalize' => 0,
		'XML::LibXML' => 0,
		'YAML::PP' => 0,
	},
	CONFIGURE_REQUIRES => {
		'ExtUtils::MakeMaker' => 0,
		'File::ShareDir::Install' => 0,
	},
	TEST_REQUIRES => {
		'App::Prove' => 0,
		'HTTP::Request::Common' => 0,
		'TAP::Parser' => 0,
		'Test2::Require::AuthorTesting' => 0,
		'Test2::V0' => 0,
	},
	test => {
		TESTS => 't/*.t t/integration/*.t',
	},
	META_MERGE => {
		resources => {
			repository => 'https://example.invalid/zuzu',
		},
	},
);

sub _script_files {
	my ( $dir, %options ) = @_;
	return if not -d $dir;

	my $skip = $options{skip} || {};
	opendir my $dh, $dir
		or die "Could not read $dir: $!";

	return map { "$dir/$_" }
		sort
		grep { !$skip->{$_} && -f "$dir/$_" }
		grep { !/^\./ }
		readdir $dh;
}

sub _install_zuzu_dispatcher_target {
	my ( $target, $destination ) = @_;
	my $zuzu = "\$(DEST${destination})\$(DFSEP)zuzu";
	my $copy = q{my ($src, $dest) = @ARGV; exit 0 if -e $dest; copy($src, $dest) or die qq{Could not copy $src to $dest: $!}; chmod 0755, $dest or die qq{Could not chmod $dest: $!}};
	$copy =~ s/\$/\$\$/g;
	return <<"MAKE";
$target :: all
\t\$(NOECHO) \$(MKPATH) "\$(DEST${destination})"
\t\$(NOECHO) \$(PERLRUN) -MFile::Copy=copy -e '$copy' bin/zuzu "$zuzu"

MAKE
}

sub MY::postamble {
	return join(
		'',
		<<'MAKE',
install :: install_zuzu_dispatcher_$(INSTALLDIRS)

install_perl :: install_zuzu_dispatcher_perl

install_site :: install_zuzu_dispatcher_site

install_vendor :: install_zuzu_dispatcher_vendor

pure_install :: install_zuzu_dispatcher_$(INSTALLDIRS)

install_zuzu_dispatcher_ :: install_zuzu_dispatcher_site

MAKE
		_install_zuzu_dispatcher_target(
			'install_zuzu_dispatcher_perl',
			'INSTALLSCRIPT',
		),
		_install_zuzu_dispatcher_target(
			'install_zuzu_dispatcher_site',
			'INSTALLSITESCRIPT',
		),
		_install_zuzu_dispatcher_target(
			'install_zuzu_dispatcher_vendor',
			'INSTALLVENDORSCRIPT',
		),
	);
}
