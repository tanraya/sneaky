#!/usr/bin/env ruby

require 'rubygems'
require 'bundler/setup'
require 'thor'

# Command-line tool to manage servers
class Sneaky < Thor
  include Thor::Actions

  source_root File.realpath((__FILE__) + '/../../templates')

  SERVER_IP         = '79.99.1.143'
  NGINX_SCRIPT      = "/etc/init.d/nginx"
  NGINX_CONFIG      = "/etc/nginx/nginx.conf"
  SERVERS_DIR       = "/etc/nginx/sites-enabled"
  NGINX_CONFIG_TPL  = "nginx.conf"
  SERVER_CONFIG_TPL = "server.erb"

  desc "addproject" ,"Add new project directory, user, configs and stuff"
  method_option :domain,  :aliases => "-n", :desc => "project domain name"
  method_option :restart, :aliases => "-r", :desc => "restart nginx after create project"

  # Create new project directory. This also creates new user.
  def addproject
    if yes?("This creates new project with name '#{project_name}'. Proceed?")
      create_user
      create_project
      create_nginx_server
      create_mysql_user
      restart_nginx

      say %Q(
        Project '#{project_name}' successfully created!
        -----------------------------------------------
        Location:       /home/#{project_name}
        User:           #{project_name}
        User password:  #{@user_password}
        Mysql user:     #{project_name}
        Mysql password: #{@mysql_user_password}
        Database:       #{project_name}
        -----------------------------------------------
      ), :yellow
    end
  end

  desc "removeproject" ,"Remove project directory, user, configs and stuff"
  method_option :domain,  :aliases => "-n", :desc => "project domain name"
  method_option :restart, :aliases => "-r", :desc => "restart nginx after create project"

  # Remove project directory. This also removes user and dependencies.
  def removeproject
    if yes?("Are you sure to remove project '#{project_name}'?")
      remove_user
      remove_nginx_server
      remove_mysql_user
      restart_nginx

      say "Project '#{project_name}' was removed", :yellow
    end
  end

  desc "nginxconfig" ,"Re-create nginx config at #{NGINX_CONFIG}"
  method_option :restart, :aliases => "-r", :desc => "restart nginx after re-create config"

  # Remove project directory. This also removes user and dependencies.
  def nginxconfig
    create_nginx_config
    restart_nginx
  end

private

  def say(msg, color=nil)
    super("\n\n#{msg}\n\n", color)
  end

  def server_ip
    SERVER_IP
  end

  # Normalize project name
  def project_name
    options.domain.gsub(/[^a-z0-9-]+/i, '_').downcase
  end

  def domain_name
    options.domain.downcase
  end

  # Create system user and user home directory
  def create_user
    @user_password = generate_password
    run "useradd #{project_name} -p #{@user_password.crypt(project_name)} -s /bin/bash"
  end

  # Create project directory structure
  def create_project
    run "mkdir /home/#{project_name}"
    run "mkdir /home/#{project_name}/config"
    run "mkdir /home/#{project_name}/htdocs"
    run "mkdir /home/#{project_name}/htdocs/shared"
    run "mkdir /home/#{project_name}/htdocs/shared/pids"
    run "mkdir /home/#{project_name}/htdocs/shared/sockets"
    run "mkdir /home/#{project_name}/htdocs/shared/db"
    run "mkdir /home/#{project_name}/htdocs/shared/db/sphinx"
    run "chown -R #{project_name}:#{project_name} /home/#{project_name}"
  end

  # Create project config for nginx server
  # TODO: Move server config to user config directory
  def create_nginx_server
    template SERVER_CONFIG_TPL, File.join(SERVERS_DIR, project_name)
  end

  def create_nginx_config
    copy_file NGINX_CONFIG_TPL, NGINX_CONFIG
  end

  # Create mysql user and grant privileges for new user
  def create_mysql_user
    @mysql_user_password = generate_password
    execute "CREATE DATABASE #{project_name} CHARACTER SET utf8 COLLATE utf8_general_ci"
    execute "GRANT ALL ON #{project_name}.* TO '#{project_name}'@'localhost' IDENTIFIED BY '#{@mysql_user_password}';"
  end

  # Restart Nginx
  def restart_nginx
    run "#{NGINX_SCRIPT} restart" if options.restart
  end

  # Remove user and project directory structure
  def remove_user
    run "userdel -r #{project_name}"
  end

  # Remove project config from nginx
  def remove_nginx_server
    run "rm #{File.join(SERVERS_DIR, project_name)}"
  end

  def remove_mysql_user
    execute "DROP DATABASE #{project_name}"
    execute "DROP USER '#{project_name}'@'localhost'"
  end

  def generate_password(size = 8)
    charset  = %w{ 2 3 4 6 7 9 A C D E F G H J K M N P Q R T V W X Y Z}
    password = (0...size).map do
      x = charset.to_a[rand(charset.size)]
      x.downcase! if rand > 0.5
      x
    end.join
  end

  def execute(sql)
    @root_login    ||= ask "Enter MySql root login:"
    @root_password ||= ask "Enter MySql root password:"

    password = "-p#{@root_password}" if @root_password.size > 0
    run %Q/mysql -u #{@root_login} #{password} -e "#{sql}"/
  end

end

Sneaky.start