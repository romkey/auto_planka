#! /usr/bin/env ruby

require 'pg'
require 'json'
require 'dotenv/load'

db = PG.connect(ENV['POSTGRESQL'])

config = JSON.parse(File.read('config.json'), symbolize_names: true)

results = db.exec("SELECT * from BOARD")
results.each do |row|
  puts row['name'], row['id']
end

loop do 
  users = db.exec("SELECT * from USER_ACCOUNT")
#  users.each do |row|
#    puts row['name']
#  end

  timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S.%L')

  config[:public_board_ids].each do |board_id|
    puts "checking board #{board_id}"
    users.each do |user|
      user_id = user['id']
      db.exec("INSERT INTO board_membership VALUES (next_id(), '#{board_id}', '#{user_id}', '#{timestamp}', NULL, 'editor', NULL) ON CONFLICT DO NOTHING");
    end
  end

  sleep(60)
end


# INSERT ... ON CONFLICT DO NOTHING/UPDATE
# https://stackoverflow.com/questions/4069718/postgres-insert-if-does-not-exist-already
