require "rails_helper"

# Issue #313 — la note interne du séjour devient du texte riche.
#
# Ce module tient les deux règles que cinq appelants partagent : la conversion du
# texte brut historique vers le HTML, et la reconnaissance d'un éditeur vidé.
RSpec.describe Stays::InternalNote do
  describe ".to_html" do
    # C'est le contrat de la MIGRATION : elle reproduit `simple_format`, pour
    # qu'une note existante s'affiche exactement comme avant la bascule.
    it "transforme deux sauts de ligne en deux paragraphes" do
      html = described_class.to_html("Premier bloc.\n\nDeuxième bloc.")

      expect(html).to include("<p>Premier bloc.</p>")
      expect(html).to include("<p>Deuxième bloc.</p>")
    end

    it "transforme un saut de ligne simple en retour à la ligne dans le même paragraphe" do
      html = described_class.to_html("Ligne A\nLigne B")

      expect(html).to include("<br />")
      expect(html.scan("<p>").size).to eq(1)
    end

    it "échappe le HTML saisi à la main dans l'ancienne colonne de texte brut" do
      expect(described_class.to_html("<script>alert(1)</script>")).not_to include("<script>")
    end

    it "rend une chaîne vide pour une note vide ou nulle — aucun paragraphe fantôme" do
      expect(described_class.to_html(nil)).to eq("")
      expect(described_class.to_html("   \n ")).to eq("")
    end
  end

  describe ".blank?" do
    # LE piège de la bascule : un éditeur de texte riche vidé ne renvoie pas "".
    it "reconnaît le HTML creux que renvoie un éditeur vidé" do
      expect(described_class).to be_blank("<div><br></div>")
      expect(described_class).to be_blank("<p><br></p>")
      expect(described_class).to be_blank("")
      expect(described_class).to be_blank(nil)
    end

    it "ne confond pas une note réelle avec du vide" do
      expect(described_class).not_to be_blank("<p>Vu avec Malau.</p>")
    end
  end

  describe ".plain_text" do
    it "extrait le texte sans le balisage" do
      expect(described_class.plain_text("<p>Sans <strong>gluten</strong>.</p>"))
        .to eq("Sans gluten.")
    end
  end
end
