require "rails_helper"

# Issue #15, Phase 2 — garde-fou principal contre les trous de traduction.
#
# Toutes les chaînes des pages client à jeton vivent dans `config/locales/public*.yml`
# (scope `public.*`). Cette spec échoue dès qu'une clé existe dans une langue et pas
# dans les autres : c'est elle qui empêche qu'une nouvelle chaîne FR parte en prod
# sans son pendant NL/EN.
RSpec.describe "Parité des clés de traduction des pages client (public.*)" do
  locales = %w[fr nl en].freeze

  # Aplatit un hash imbriqué en clés pointées : {a: {b: 1}} => ["a.b"]
  def flatten_keys(hash, prefix = nil)
    hash.flat_map do |key, value|
      path = [prefix, key].compact.join(".")
      value.is_a?(Hash) ? flatten_keys(value, path) : [path]
    end
  end

  # Fusionne tous les public*.<locale>.yml et renvoie les clés sous le scope `public`.
  def public_keys_for(locale)
    files = Dir[Rails.root.join("config", "locales", "public*.#{locale}.yml")]
    expect(files).not_to be_empty, "aucun fichier config/locales/public*.#{locale}.yml"

    tree = files.reduce({}) do |acc, file|
      loaded = YAML.load_file(file)[locale] || {}
      acc.deep_merge(loaded)
    end

    flatten_keys(tree["public"] || {}).sort
  end

  let(:keys) { %w[fr nl en].index_with { |locale| public_keys_for(locale) } }

  it "définit au moins les clés de la page booking et de la page séjour en FR" do
    expect(keys["fr"]).to include("bookings.show.heading", "stays.show.title", "language_menu.label")
  end

  (locales - ["fr"]).each do |locale|
    it "#{locale.upcase} couvre exactement les mêmes clés que le FR" do
      missing = keys["fr"] - keys[locale]
      extra   = keys[locale] - keys["fr"]

      expect(missing).to be_empty,
                         "clés absentes en #{locale.upcase} : #{missing.join(', ')}"
      expect(extra).to be_empty,
                       "clés présentes en #{locale.upcase} mais pas en FR : #{extra.join(', ')}"
    end
  end

  it "ne laisse aucune valeur vide dans les 3 langues" do
    %w[fr nl en].each do |locale|
      blanks = public_keys_for(locale).reject do |key|
        I18n.t(key, scope: "public", locale: locale, default: nil).present?
      end

      expect(blanks).to be_empty, "valeurs vides en #{locale.upcase} : #{blanks.join(', ')}"
    end
  end
end
