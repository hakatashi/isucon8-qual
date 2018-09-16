# https://re-engines.com/2018/08/13/rails-puma-performance-tuning/
threads 5, 5
workers 3
preload_app!

stdout_redirect "/home/isucon/torb/webapp/ruby/log/puma.stdout.log", "/home/isucon/torb/webapp/ruby/log/puma.stderr.log", true
