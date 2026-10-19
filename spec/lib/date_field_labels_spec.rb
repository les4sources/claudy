require "rails_helper"

# Un `date_field` du `TailwindFormBuilder` pose SON intitulé, tiré du nom du
# champ : sur un formulaire sans modèle, `:from` devient « From » et `:to`
# « To ». Posé sous un `f.label` qui dit déjà « Du » ou « Au », le champ
# s'affichait sous deux intitulés (Michael, 2026-10-19, Trésorerie). Ce
# recensement lit les vues : un `f.label :x` suivi de son `f.date_field :x`
# doit lui passer `label:` (en général `label: false`).
RSpec.describe "Intitulés des sélecteurs de date" do
  INTITULE_DE_CHAMP = /\A\s*=\s*(\w+)\.label :(\w+)/
  SELECTEUR_DE_DATE = /\A\s*=\s*(\w+)\.date_field :(\w+)/

  def doublons
    Dir[Rails.root.join("app/views/**/*.slim")].sort.flat_map do |chemin|
      lignes = File.readlines(chemin, chomp: true)
      # Les formulaires qui reprennent le builder d'ActionView n'ont pas
      # d'intitulé automatique : leur `f.label` est le seul.
      next [] if lignes.any? { |l| l.include?("builder: ActionView::Helpers::FormBuilder") }

      lignes.each_index.filter_map do |index|
        intitule = lignes[index - 1].match(INTITULE_DE_CHAMP) if index.positive?
        champ = lignes[index].match(SELECTEUR_DE_DATE)
        next unless intitule && champ && intitule.captures == champ.captures

        # L'appel peut courir sur plusieurs lignes d'options (`label: …`).
        suite = [lignes[index]] + lignes.drop(index + 1).take_while { |l| l.strip.match?(/\A\w+:/) }
        next if suite.join(" ").include?("label:")

        "#{chemin.delete_prefix("#{Rails.root}/")}:#{index + 1}"
      end
    end
  end

  it "ne double jamais l'intitulé d'un sélecteur de date" do
    expect(doublons).to be_empty
  end
end
