require 'open3'
require 'json'
require 'chef'
require 'socket'
require 'chef/search/query'

hostname = Socket.gethostname
environment_name = 'rundeck'
Chef::Config.from_file("#{ENV['HOME']}/.chef/knife.rb")

def run(command, working_directory="/")
  puts "Running #{command}"
  output = []
  Open3.popen2e(command, :chdir=>"#{working_directory }") do |stdin, stdout_err, wait_thr|
    while line = stdout_err.gets
      output << line
    end
    output.each {|line| puts line}
    raise "Error while running #{command}" if not wait_thr.value.success?
    return wait_thr.value.success?, output
  end
end

def update_rundeck_master
  # Assumming the current instance is the master
  command = "/usr/bin/sudo /usr/bin/chef-client"
  exit_code, output = run(command)
  raise exit_code if exit_code != 0
end

def update_cname(cname, domain)

	puts "Updating #{cname} to point to #{domain}"
	exit_code, output = run("forge quarry rrs find --where_name #{cname}")

	

declare -i RESULT=0

forge quarry rrs update --key $rr_id --value $master
RESULT+=$?
forge quarry sync zones
RESULT+=$?
forge quarry sync zones
RESULT+=$?
  
end

def update_rundeck_standby
end


searcher = Chef::Search::Query.new.search(:environment, "name:#{environment_name}") do |env|
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
	update_rundeck_standby

      else
	puts "This instance is already the master in chef_environment: #{environment_name} so nothing to do"
      end
      
    end
  end
end

