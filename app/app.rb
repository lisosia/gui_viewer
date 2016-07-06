# -*- coding: utf-8 -*-

require 'sinatra'
require 'sinatra/reloader'
require 'sinatra/config_file'

set :root, File.expand_path( '../../.', __FILE__)

$LOAD_PATH.push( File.dirname(__FILE__) )
require 'myconfig'
$SETTINGS = MyConfig.new( './config.yml' )
require "init.rb"
include MyLog

rack_logger = Logger.new('./log/app.log')

configure do
  use Rack::CommonLogger, rack_logger
end

before do
  unless File.exists? $SETTINGS.storage_root
    raise "invalid storage_root path<#{settings.storage_root}> specified in configfile<#{config_file_path}>"
  end
  @table = NGS::readCSV( $SETTINGS.ngs_file )
  @show_headers = ['slide', 'run_name', 'application', 'library_id']
end


get '/' do
  @max_slide = 2**30
  @min_slide = -1
  if @params[:range] and /\A[0-9]+-[0-9]+/ === @params[:range]
    @min_slide , @max_slide = @params[:range].split('-').map{|v| v.chomp.to_i}
  end
  @filtered_table = slide_filtered_table(@table)
  @show_headers = ['slide', 'run_name', 'application', 'library_id', 'prep_kit']

  haml :table, :locals => {:check_dir => @params[:check_dir]}
end

def slide_filtered_table(table, include_not_num = false)
  table.group_by{|r| r.values_at('slide').first}.select{|k,v| (include_not_num and !( /\A[-+]?[0-9]+\z/ === k) ) or (k.to_i <= @max_slide and k.to_i >= @min_slide) }
end

post '/' do
  slide = @params[:slide]
  
  return "empty post; please return to previous page" if @params[:check].nil? 
  rows = @table.select{|r| r['slide'] == slide}
  library_ids_checked = params[:check].map{ |lib_id| @table.select{|r| r['library_id'] == lib_id}[0] }
  mylog.info 'post / called. slide=#{slide}; checked_ids=#{library_ids_checked}'
  raise "internal eoor; not such slide<#{slide}>" if library_ids_checked.any?{ |r| r.nil? }
  
  ok, prepkit = validate_prepkit( library_ids_checked )
  unless ok
    return haml( :error, :locals => { :unknown_prepkit => prepkit } )
  end


  prepare(slide, library_ids_checked )


  redirect to('/')
end

get '/all' do
  @show_headers = NGS::HEADERS
  haml :table
end

get '/graph/:slide' do
  slide = @params[:slide]
  unless File.exist? "#{$SETTINGS.root}/public/graph/#{slide}.png"
    mk_graph(slide)
  end
  haml :graph , :locals => {:slide => "#{slide}"}
end

post '/graph/:slide' do
  slide = @params[:slide]
  mk_graph(slide)
  redirect to("/graph/#{slide}")
end

def mk_graph(slide)
  if slide.include? '/'
    mylog.warn "invalud reqest slide=[#{slide}]"
    return
  end
  system <<EOS
mkdir -p #{$SETTINGS.root}/public/graph
cd #{$SETTINGS.root}/public/graph && cat #{$SETTINGS.storage_root}/#{slide}/check_results.log | python #{$SETTINGS.root}/etc/mk_graph/mk_graph.py
mv tmp.png #{$SETTINGS.root}/public/graph/#{slide}.png
EOS
  redirect to "/graph/#{slide}"
end

get '/process' do
  tasks = TaskHgmd.run_sql("select pid,status,args,uuid from tasks order by uuid desc limit 5")
  tasks.map{|e| e.inspect}.join("<br>")

  haml :process ,:locals=>{:tasks => tasks}
end

get '/progress/:slide' do
  d = Dir.glob( File.join($SETTINGS.storage_root, params['slide'], "*" ) ).select{|f| File.directory? f}
  def cont(dr)
    file = File.join dr,"make.log.progress"
    if File.exist? file 
      `cat #{file}`
    else
      "! file-not-exist" 
    end	
  end

  show = d.map{ |e|  [ e, cont(e) ] }
  progresses = show.map{|f| f[0] + "; " + f[1] }.join("<br>")
  
  def check_results(slide)
    file = File.join $SETTINGS.storage_root, slide, "check_results.log"
    if File.exist? file
      `cat #{file} | grep "WARNING"`
    else
      "! file-not-exists"
    end

    
  end

  "check_results 's WARNING(s)<BR/>
#{check_results( @params[:slide] )}
<BR/><BR/>
#{progresses}
"
end

def dir_slide_exist?(slide)
  slide = slide.to_s
  raise 'invalid arg' if slide == ''
  return File.directory? File.join($SETTINGS.storage_root, slide)
end

def dir_exists?(slide, library_id, prep_kit)
  raise "args include nil" if slide.nil? or library_id.nil?
  p = $SETTINGS.storage_root + '/' + slide.to_s + '/' + library_id.to_s + get_suffix(prep_kit)
  #return p
  File.exists? p
end

class UnknownPrepkitError < StandardError
  attr_reader :prepkit
  def initialize(prepkit)
    @message = prepkit
  end  
end

module Prepkit
  @@loaded = YAML.load_file('./config.yml')['prepkit_info']
  @@data = []
  for arr in @@loaded # arr == [regex, suffix, surepos_filepath]
    @@data << [ Regexp.new(arr[0]), arr[1], arr[2] ]
  end

  def self.get( prepkit )
    for arr in @@data
      return [ arr[1], arr[2] ] if arr[0] === prepkit
    end
    return  nil
  end

end

mylog.warn Prepkit::get('Agilent SureSelect v6+UTR')

def get_suffix(prep_kit)
  case prep_kit
  # when /^N.A./ then return ''
  when /^Illumina TruSeq/ then return '_TruSeq'
  when /^Agilent SureSelect custom 0.5Mb/ then return '_SSc0_5Mb'
  when /^Agilent SureSelect custom 50Mb/ then return '_SS50Mb'
  when /^Agilent SureSelect v4\+UTR/ then return '_SS4UTR'
  when /^Agilent SureSelect v5\+UTR/ then return '_SS5UTR'
  when /^Agilent SureSelect v6\+UTR/ then return '_SS6UTR'
  when /^Agilent SureSelect v5/ then return '_SS5'
  when /^Amplicon/ then return '_Amplicon'
  when "RNA" then return '_RNA'
  when /^TruSeq DNA PCR-Free Sample Prep Kit/ then return '_WG'
  else
    STDERR.puts "WARNING Uninitilalized value; #{prep_kit}"
    return [nil,  prep_kit ]
  end  
end

# to avoid uncaught throw <- cannot catch error over threads
def validate_prepkit(checked)
  checked.group_by{|r| r['prep_kit']}.each do |prep, row| 
    ok, info = get_suffix( prep )
    return [false, prep ] unless ok
  end
  return true
end

# - checked - Array of CSV::Row
def prepare(slide, checked)
  raise 'internal_error' unless ( checked.is_a? Array and checked[0].is_a? CSV::Row)

  checked.group_by{|r| r['prep_kit']}.each do |prep, row| 
    prepare_same_suffix(slide, row)
  end
  return nil
end

def prepare_same_suffix(slide, checked)
  mylog.info "prepare_same_suffix called; #{slide}, #{checked}"
  # get run-name from NGS-file
  prep_kits = checked.map{|r| r['prep_kit'] }

  raise 'internal_error' unless prep_kits.uniq.size == 1
  suffix = get_suffix( prep_kits[0] )

  run_name = NGS::get_run_name(checked)
  ids = checked.map{|r| r['library_id']}
  storage = File.join( $SETTINGS.storage_root, slide)

  cmd = <<-EOS
  perl #{$SETTINGS.root}/calc_dup/make_run_takearg.pl --run #{slide} --run-name #{run_name} --suffix #{suffix} --library-ids #{ids.join(',')} --storage #{storage} --path-check-result #{$SETTINGS.root}/calc_dup/check_results.sh --path-makefile #{$SETTINGS.makefile_path}
        EOS
  
  Dir.chdir($SETTINGS.storage_root){
    File.open("./#{slide}.tmplog___", 'w') {|f| f.write(cmd) }
    `#{cmd}`
  }

  # TaskHgmd.spawn("./etc/dummy.sh" , slide ,ids, $SETTINGS.root )
  TaskHgmd.spawn("./auto_run#{suffix}.sh" , slide, ids, storage)

end