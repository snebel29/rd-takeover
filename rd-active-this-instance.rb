#!/usr/bin/env ruby

require 'open3'
require 'json'
require 'chef'
require 'socket'
require 'chef/search/query'
require 'net/ssh'

#TODO: For some reason ohai attributes seems missing when running the process directly, workaround is not using them in the cookbook
hostname = Socket.gethostname
Chef::Config.from_file("#{ENV['HOME']}/.chef/knife.rb")

def run(command, working_directory="/")
  puts "Running #{command}"
  output = []
  Open3.popen2e(command, :chdir=>"#{working_directory }") do |stdin, stdout_err, wait_thr|
    while line = stdout_err.gets
      puts line
      output << line
    end
    raise "Error while running #{command}" if not wait_thr.value.success?
    return wait_thr.value.success?, output
  end
end

def higher_subdomain(domain)
  domain.split('.')[0]
end

def update_rundeck_master
  # Assumming the current instance is the master
  command = "/usr/bin/sudo /usr/bin/chef-client"
  exit_code, output = run(command)
end

def update_cname(cname, master)

        puts "Update #{cname} in order to point to #{master}"
        exit_code, output = run("forge quarry rrs find --where_name #{higher_subdomain(cname)}")
  rr_id = nil

  output.each do |line|
    if line =~ /^*.rr_id: (\d+)/
      rr_id = $1
      exit_code, output = run("forge quarry rrs update --key #{rr_id} --value #{higher_subdomain(master)}")
      exit_code, output = run("forge quarry sync zones")
    end
  end
  if rr_id.nil?
      puts "regexp result: #{output =~ /^*.rr_id: (\d+)/}"
      puts "Failed trying to capture rr_id from woodstove"
      exit(1)
  end

end

def update_rundeck_standby(target)
  begin
    ssh = Net::SSH.start(target, ENV['USER'])
    output = ssh.exec!("sudo chef-client")
    ssh.close
    puts output
  rescue
    puts "Unable to connect to #{target}"
    exit(2)
  end
end

# MAIN
chef_environment = nil
Chef::Search::Query.new.search(:node, "name:#{hostname}") {|node| chef_environment = node.chef_environment}

Chef::Search::Query.new.search(:environment, "name:#{chef_environment}") do |env|
  env.default_attributes['clusters'].each do |cluster|
    if cluster.has_value?(hostname)
      master = cluster['master']
      standby = cluster['standby']

      if master != hostname

        cluster['master'] = hostname
        cluster['standby'] = master
        env.save

              puts "This is the new environment configuration"
              puts JSON.pretty_generate(env.default_attributes)

              update_rundeck_master
              update_cname(cluster['cname'], cluster['master'])
              update_rundeck_standby(cluster['standby']) if File.basename(__FILE__) != 'rd-failover'
	      exit(0)
      else
              puts "This instance is already the master in chef_environment [#{chef_environment}] so nothing to do"
              exit(0)
      end
    end
  end
  puts "This host [#{hostname}] is not in the environment [#{node.chef_environment}] configuration"
  exit(1)
end

