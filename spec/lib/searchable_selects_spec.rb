require "rails_helper"

# « Listes déroulantes = toujours cherchables » (Michael, 2026-09-30, rappelé
# le 2026-10-17). Une règle de vue qu'aucun écran ne fait respecter tout seul :
# le 2026-10-17, 82 listes des écrans Finances étaient encore des <select> nus,
# dont le plan comptable du grand livre. D'où ce recensement, qui lit les vues
# plutôt que de les rendre — une liste dans une branche rarement affichée
# (un formulaire d'erreur, un gabarit de ligne) compte autant que les autres.
#
# Le périmètre est `app/views/finance` : c'est là que la règle est tenue. Une
# autre section rejoint le recensement en s'ajoutant à DOSSIERS une fois
# convertie.
RSpec.describe "Listes déroulantes cherchables" do
  DOSSIERS = %w[app/views/finance].freeze

  # Un appel de liste, sans les `.select { … }` de Ruby qui filtrent un tableau.
  APPEL = /(\b[a-z_]+\.select[ (]|collection_select|select_tag|grouped_collection_select)/
  FILTRE_RUBY = /\.select\s*(\{|\(&|do\b)/

  # L'instruction entière : un appel Slim peut courir sur plusieurs lignes
  # (virgule en fin de ligne, parenthèses ou crochets encore ouverts).
  def instruction(lignes, debut)
    texte = lignes[debut]
    fin = debut
    ouverts = ->(t) { t.count("([{") - t.count(")]}") }
    profondeur = ouverts.(texte)
    while (texte.rstrip.end_with?(",", "\\") || profondeur.positive?) && fin + 1 < lignes.size
      fin += 1
      texte += "\n#{lignes[fin]}"
      profondeur += ouverts.(lignes[fin])
    end
    [texte, fin]
  end

  def listes_nues
    DOSSIERS.flat_map { |dossier| Dir[Rails.root.join(dossier, "**/*.slim")] }.sort.flat_map do |chemin|
      lignes = File.readlines(chemin, chomp: true)
      nues = []
      index = 0
      while index < lignes.size
        ligne = lignes[index]
        if ligne.match?(APPEL) && !ligne.match?(FILTRE_RUBY) && !ligne.strip.start_with?("/")
          texte, index = instruction(lignes, index)
          nues << "#{chemin.delete_prefix("#{Rails.root}/")}:#{ligne.strip[0, 80]}" unless texte.include?("searchable_select_target")
        end
        index += 1
      end
      nues
    end
  end

  it "fait passer chaque <select> des écrans Finances par searchable-select" do
    expect(listes_nues).to be_empty
  end

  # Un <select> marqué sans son champ de recherche est pire qu'une liste nue :
  # le contrôleur le masque et il n'y a plus rien à cliquer. Le champ vient du
  # partial, ou s'écrit en ligne quand il lui faut une autre largeur.
  it "donne à chaque liste marquée son champ de recherche" do
    sans_champ = DOSSIERS.flat_map { |dossier| Dir[Rails.root.join(dossier, "**/*.slim")] }.filter_map do |chemin|
      texte = File.read(chemin)
      listes = texte.scan("searchable_select_target").size
      champs = texte.scan("shared/searchable_select_search").size +
               texte.scan('data-searchable-select-target="wrap"').size
      "#{chemin.delete_prefix("#{Rails.root}/")} : #{listes} liste(s), #{champs} champ(s)" if listes != champs
    end

    expect(sans_champ).to be_empty
  end
end
