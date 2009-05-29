require 'rubygems'
require 'rake'
require 'net/http'
require 'active_record'
require "#{File.dirname(__FILE__)}/../config/environment.rb"

namespace :solr do

  def pid_path
    ENV['PID_PATH'] || "#{RAILS_ROOT}/tmp/pids/solr_#{RAILS_ENV}.pid"
  end

  desc 'Starts Solr. Options accepted: PID_PATH, RAILS_ENV, SOLR_HOME'
  task :start => :environment do

    plugin_path = File.dirname(__FILE__) + "/../jetty"

    begin
      n = Net::HTTP.new( SOLR_HOST , SOLR_PORT)
      n.request_head('/').value 

    rescue Net::HTTPServerException #responding
      puts "Port #{SOLR_PORT} in use" and return

    rescue Errno::ECONNREFUSED, Errno::ENETUNREACH #not responding
      options = {
        'solr.solr.home' => SOLR_PATH,
        'solr.data.dir' => File.join(SOLR_PATH, 'data', RAILS_ENV),
        'jetty.host' => SOLR_HOST,
        'jetty.port' => SOLR_PORT,
        'jetty.logs' => "#{File.join( RAILS_ROOT, 'log' )}",
        'rails.env' => RAILS_ENV,
        'java.util.logging.config.file' => File.join( SOLR_PATH, 'config', 'logging.properties' )
      }.map { |k,v| "-D#{k}=#{v}" }.join( " " )

      Dir.chdir( plugin_path ) do
        pid = fork do
          exec "java #{options} -jar start.jar"
        end
        sleep(5)
        File.open( pid_path , "w"){ |f| f << pid}
        puts "#{ENV['RAILS_ENV']} Solr started successfully on #{SOLR_PORT}, pid: #{pid}."
      end
    end
  end
  
  desc 'Stops Solr. Options accepted: PID_PATH, RAILS_ENV, SOLR_HOME'
  task :stop => :environment do
    fork do
      if File.exists?(pid_path)
        File.open(pid_path, "r") do |f|
          pid = f.readline
          Process.kill('TERM', pid.to_i)
        end
        File.unlink(pid_path)
        Rake::Task["solr:destroy_index"].invoke if RAILS_ENV == 'test'
        puts "Solr shutdown successfully."
      else
        puts "Solr is not running.  I haven't done anything."
      end
    end
  end
  
  desc 'Remove Solr index'
  task :destroy_index => :environment do
    if File.exists?("#{SOLR_PATH}/data/#{RAILS_ENV}")
      Dir[ SOLR_PATH + "data/#{RAILS_ENV}/index/*"].each{|f| File.unlink(f)}
      Dir.rmdir(SOLR_PATH + "/data/#{RAILS_ENV}/index")
      puts "Index files removed under " + RAILS_ENV + " environment"
    end
  end

  desc 'Rebuild solr index'
  task :rebuild_index => :environment do
    
    if ENV['start'].blank?
      ActsAsSolr::Post.rebuild_indexes
    else
      ActsAsSolr::Post.rebuild_indexes( 100 ) do |ar, options|
        ar.all(options.merge({:order => 'id', :conditions => [ 'updated_at > ?', ENV['start'].to_i.days.ago ]}))
      end
    end
    
  end

  desc 'Starts Solr and rebuilds your index'
  task :setup => :environment do
    Rake::Task["solr:start"].invoke
    sleep(5)
    ActsAsSolr::Post.rebuild_indexes
  end

end