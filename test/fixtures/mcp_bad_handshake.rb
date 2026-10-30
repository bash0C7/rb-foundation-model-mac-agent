# frozen_string_literal: true

File.write(ARGV.fetch(0), Process.pid.to_s)
$stdout.puts "not json"
$stdout.flush
$stdin.read
