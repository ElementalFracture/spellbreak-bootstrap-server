import Config

if File.exists?("#{Path.dirname(__ENV__.file)}/dev.secret.exs") do
  import_config "dev.secret.exs"
end
