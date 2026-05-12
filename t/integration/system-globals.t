use Test2::V0;

use Zuzu::Parser;
use Zuzu::Runtime;

my $parser = Zuzu::Parser->new;

sub eval_src {
	my ( $src, $runtime_args ) = @_;
	my $runtime = Zuzu::Runtime->new( %{ $runtime_args // {} } );
	my $ast = $parser->parse( $src, "system-globals.zzs" );

	return $runtime->evaluate($ast);
}

is eval_src(<<"SRC"), "Zuzu::Runtime", "__system__ exposes runtime name";
__system__{runtime};
SRC

is eval_src(<<"SRC"), "0", "__system__ exposes language version";
"" _ __system__{language_version};
SRC

like eval_src(<<"SRC"), qr/\A\d+\.\d{6}\z/, "__system__ exposes perl version";
"" _ __system__{perl_version};
SRC

is eval_src(
	'__system__{inc}[0] _ ":" _ __system__{inc}[1];',
	{
		lib => [ "/opt/zuzu/modules", "/tmp/extra/modules" ],
	}
), "/opt/zuzu/modules:/tmp/extra/modules",
	"__system__ exposes lib search paths as Array";

like(
	dies {
		eval_src(<<"SRC", { lib => [ "/opt/zuzu/modules" ] });
__system__{inc}.append( "/tmp/other" );
SRC
	},
	qr/Cannot modify __system__/,
	"__system__ rejects inc array mutation",
);

is eval_src(<<"SRC"), "ok", "__global__ is writable";
__global__.set( "mode", "ok" );
__global__{mode};
SRC

like(
	dies {
		eval_src(<<"SRC");
__system__.set( "runtime", "X" );
SRC
	},
	qr/Cannot modify __system__/,
	"__system__ rejects dict method mutation",
);

like(
	dies {
		eval_src(<<"SRC");
__system__{runtime} := "X";
SRC
	},
	qr/Cannot modify __system__/,
	"__system__ rejects dict assignment mutation",
);

like(
	dies {
		eval_src(<<"SRC");
__system__ := {};
SRC
	},
	qr/Cannot assign to const '__system__'/,
	"__system__ binding is const",
);

done_testing;
