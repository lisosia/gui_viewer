> this is a private app. this doc is written for me

# gui viewer

web based app to process data

## what this app does

1. load NGS_\*\*\* file to get info about run,sampleid,prepkit,,, etc
2. show list of samples by run on the web
3. you can launch task to process data of samples you selected

## how to use

1. place config.yml at app root.
2. place NGS_\*\*\*.csv file, makefile at the place config.yml specified.
3. bundle install
4. bundle exec ruby app/app.rb -o 0.0.0.0 # -o is a options to set ip address app(Rack) use

## app structure

+ simple Ruby app based on framework [][sinatra]  
+ use some perl, python code for process data

#### directory structure

+ app/ - main sinatra codes
+ config.yml - config file
+ views/ - sinatra views ( [][haml] files used by ruby )
+ calc_dup/ - reused code written before
+ etc/ - etc
+ sim/ - for debug

#### misc

a ruby library is called 'gem'.  
It is a little complicated to controll ruby-version and gem version.

sinatra や Raild は [][Rack] の上に構築されたフレームワークです。ややこしいのでスルー推奨.  
[参考][http://sugamasao.hatenablog.com/entry/20120213/1329152534]

同一システム内で複数の ruby の version を使いたい/切り替えたいときは rbenv を使います。 (似た者としてrvmがあるが rbenvのほうがよい )  
app を動かすだけならば、システムに最初から入っている ruby を使って問題ないと思います。開発は ruby1.9.3p484 で行いました。
[参考: rbenv を利用した Ruby 環境の構築][http://dev.classmethod.jp/server-side/language/build-ruby-environment-by-rbenv/]  

gem の管理には gem コマンドが使えます. gem の wrapper として bundle を使うのが常道です。  
[参考][http://shokai.org/blog/archives/7262] . 
[使い方][http://qiita.com/hisonl/items/162f70e612e8e96dba50]

rbenv と gem(bundler) を併用する場合は、おなじ gem でも rubyのverson ごとに複数 install されることに注意。ここらへんはややこしいです。

[sinatra]:www.github.com/sinatra/sinatra
[haml]:http://morizyun.github.io/blog/beginner-rails-tutorial-haml/
[rbenv]:https://github.com/rbenv/rbenv
[rack]:http://rack.github.io/