BEGIN {
	require 5.005;

	# Architecture check for SerialPort driver
	$serialport_driver="Device::SerialPort";
	$serialport_version="1.0";
	if( $^O =~ /Win/io ) {
		$serialport_driver="Win32::SerialPort";
		$serialport_version="0.07";
	}
}
use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'      => 'sendpage',
    'VERSION_FROM' => 'sendpage', # finds $VERSION
    'AUTHOR'  => 'Kees Cook <kees@outflux.net>',
    'ABSTRACT_FROM' => 'sendpage',
    'EXE_FILES' => [qw(sendpage snpp email2page sendmail2snpp)],
    'PREREQ_PM' => {
		'Net::SNPP' => 1.10,
		'Mail::Send' => 1.08,
		$serialport_driver => $serialport_version,		
	},
);

