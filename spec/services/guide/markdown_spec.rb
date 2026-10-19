require "rails_helper"

RSpec.describe Guide::Markdown do
  it "rend le Markdown du Guide, tableaux et cases à cocher compris" do
    html = described_class.render("## Étapes\n\n- [ ] Remplir\n- [x] Déposer\n\n| Banque | IBAN |\n|---|---|\n| Triodos | BE00 |").to_html

    expect(html).to include(%(<h2 id="étapes">), %(href="#étapes"), %(type="checkbox"), "<table>", "<td>Triodos</td>")
  end

  it "ne rend ni HTML brut ni lien javascript: — tout le monde lit le Guide" do
    html = described_class.render("<script>alert(1)</script>\n\n[piège](javascript:alert(1)) <img src=x onerror=alert(1)>").to_html

    expect(html).not_to include("<script", "javascript:", "onerror")
  end

  it "ouvre les liens externes dans un nouvel onglet, pas les liens internes" do
    html = described_class.render("[Semisto](https://semisto.org) [note de frais](/guide/pages/3)").to_html

    expect(html).to include(%(href="https://semisto.org" target="_blank" rel="noopener noreferrer"))
    expect(html).to include(%(<a href="/guide/pages/3">))
  end

  it "donne la table des matières (intertitres de niveau 2 et 3)" do
    headings = described_class.render("## Avant\n\n### Le formulaire\n\n#### Détail\n\n## Après").headings

    expect(headings.map { |h| [h.level, h.text, h.anchor] })
      .to eq([[2, "Avant", "avant"], [3, "Le formulaire", "le-formulaire"], [2, "Après", "après"]])
  end

  it "donne un texte brut pour les extraits" do
    expect(described_class.plain_text("## Titre\n\nUn **mot** et [un lien](https://x.be).")).to eq("Titre Un mot et un lien.")
  end

  describe "liens entre pages" do
    let!(:chapitre) { GuideChapter.create!(title: "Procédures") }
    let!(:note) { GuidePage.create!(chapter: chapitre, title: "Soumettre une note de frais") }

    it "retrouve un titre à apostrophe malgré la typographie (’)" do
      depart = GuidePage.create!(chapter: chapitre, title: "Départ d'un membre")

      expect(described_class.render("[[depart d'un membre]]").to_html).to include(%(href="/guide/pages/#{depart.to_param}"))
    end

    it "lie `[[Titre]]` à la page, sans tenir compte des majuscules ni des accents" do
      html = described_class.render("Voir [[soumettre une NOTE de frais]] et [[Soumettre une note de frais|la procédure]].").to_html

      expect(html).to include(%(<a href="/guide/pages/#{note.to_param}" class="guide-wikilink">soumettre une NOTE de frais</a>))
      expect(html).to include(%(class="guide-wikilink">la procédure</a>))
    end

    it "laisse visible un titre sans page, et propose de la créer aux rédacteurs" do
      lecture = described_class.render("Voir [[Départ d'un membre]].").to_html
      expect(lecture).to include(%(<span class="guide-wikilink guide-wikilink-missing"), "Départ d’un membre")
      expect(lecture).not_to include("<a ")

      redaction = described_class.render("Voir [[Départ]].", new_page_links: true).to_html
      expect(redaction).to include(%(href="/guide/pages/new?title=D%C3%A9part"), "guide-wikilink-missing")
    end

    it "ne touche pas au code" do
      html = described_class.render("`[[Soumettre une note de frais]]`").to_html

      expect(html).to include("<code>[[Soumettre une note de frais]]</code>")
    end

    it "donne le texte affiché dans les extraits, sans chercher les pages" do
      expect(described_class.plain_text("Voir [[Une page|celle-ci]] et [[Autre]].")).to eq("Voir celle-ci et Autre.")
    end
  end
end
