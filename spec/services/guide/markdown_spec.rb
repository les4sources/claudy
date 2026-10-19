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
end
