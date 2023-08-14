requires 'Config::JSON';
requires 'DateTime';
requires 'DBIx::Class';
requires 'DBD::SQLite';
requires 'Telegram::Bot' => '0.023';
requires 'Try::Tiny';
requires 'Log::Dispatch';
requires 'Log::Dispatch::FileRotate';

suggests 'DBIx::Class::Schema::Loader';

on 'test' => sub {
    requires 'Test2::Suite';
    requires 'Test2::V0';
    requires 'Test::DBIx::Class';
};