# -*- encoding : utf-8 -*-

require 'blather/client/dsl'
require "capistrano/jabber/notifications/version"

module Capistrano
  module Jabber
    module Notifications

      module MUC
        extend Blather::DSL
        attr_accessor :conference, :uid, :msg

        def self.send_message(msg)
          @msg = msg
          EM.run do
            client.run
            EM.add_timer(5) do
              EM.stop
            end
          end
        end

        def self.stop
          EM.stop
        end

        def self.configure(conference, uid)
          @conference = conference
          @uid = uid
        end

        when_ready do
          join @conference, @uid

          echo = Blather::Stanza::Message.new
          echo.to = @conference
          echo.body = @msg
          echo.type = 'groupchat'
          client.write echo
        end
      end

      class << self

        attr_accessor :options
        attr_accessor :variables

        def deploy_started
          send_jabber_message "deploy"
        end

        def deploy_completed
          send_jabber_message "deploy", true
        end

        def rollback_started
          send_jabber_message "deploy:rollback"
        end

        def rollback_completed
          send_jabber_message "deploy:rollback", true
        end

        private

        def git_log_revisions
          current, real = variables[:current_revision][0,7], variables[:real_revision]

          if current == real
            "GIT: No changes ..."
          else
            if (diff = `git log #{current}..#{real} --oneline`) != ""
              diff = "  " << diff.gsub("\n", "\n    ") << "\n"
              "\nGIT Changes:\n" + diff
            else
              "GIT: Git-log problem ..."
            end
          end
        end

        def send_jabber_message(action, completed = false)
          app_name = variables[:repository][/\/([a-z]*)\.git/, 1]
          msg = "#{username} #{completed ? 'completed' : 'started'} #{action} #{app_name} on #{variables[:server_name]} at #{Time.now.strftime('%H:%M')} (#{variables[:branch]}@#{options[:real_revision][0, 7]})".gsub("\n", '')

          notification_group = options[:group].to_s
          notification_list = options[:members]
          conference = options[:conference]

          MUC.setup "#{options[:uid]}@#{options[:server]}", options[:password], options[:server]
          MUC.configure(conference, options[:uid])
          MUC.send_message(msg)

          true
        end

        def username
          @username ||= `whoami`
        end
      end
    end
  end
end


Capistrano::Configuration.instance(:must_exist).load do

  namespace :deploy do
    namespace :jabber do
      %w(deploy_started deploy_completed rollback_started rollback_completed).each do |m|
        task m.to_sym do
          Capistrano::Jabber::Notifications.options = {
            uid:      fetch(:jabber_uid),
            server:   fetch(:jabber_server),
            password: fetch(:jabber_password),
            group:    fetch(:jabber_group),
            conference:    fetch(:jabber_conference),
            members:  fetch(:jabber_members),
            real_revision: fetch(:real_revision),
            release_name: fetch(:release_name),
            action: m.to_sym
          }
          Capistrano::Jabber::Notifications.variables = variables
          Capistrano::Jabber::Notifications.send m
        end
      end
    end
  end

  before 'deploy',          'deploy:jabber:deploy_started'
  after  'deploy',          'deploy:jabber:deploy_completed'
  before 'deploy:rollback', 'deploy:jabber:rollback_started'
  after  'deploy:rollback', 'deploy:jabber:rollback_completed'
end
