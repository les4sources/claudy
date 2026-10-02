# Pose des variables d'environnement le temps d'un exemple, puis restaure les
# valeurs d'origine (nil = variable absente).
module EnvHelpers
  def with_env(vars)
    previous = vars.keys.to_h { |key| [key, ENV[key]] }
    vars.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end

RSpec.configure { |config| config.include EnvHelpers }
