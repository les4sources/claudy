require "rails_helper"

# Les outils MCP du Guide des 4 Sources (Michael, 2026-10-19) : lire,
# chercher, écrire une page (version signée « via Claude »), corriger un
# passage, ajouter une image, restaurer, ranger les chapitres.
RSpec.describe Mcp::Server, "Guide des 4 Sources" do
  let(:michael) { User.create!(email: "michael@les4sources.be", password: "secret123456", access_roles: %w[sourcier]) }
  let(:server) { described_class.new(user: michael) }
  let!(:procedures) { GuideChapter.create!(title: "Procédures") }

  def outil(name, arguments, serveur: server)
    serveur.handle({ "jsonrpc" => "2.0", "id" => 1, "method" => "tools/call",
                     "params" => { "name" => name, "arguments" => arguments } })[:result]
  end

  def texte(result) = result[:content].first[:text]

  def confirme(name, arguments, serveur: server)
    apercu = outil(name, arguments, serveur: serveur)
    expect(apercu[:isError]).to be(false), texte(apercu)
    resultat = outil(name, arguments.merge("confirmation" => texte(apercu)[/confirmation: "([^"]+)"/, 1]), serveur: serveur)
    expect(resultat[:isError]).to be(false), texte(resultat)
    resultat
  end

  it "crée une page, la lit, la corrige, puis la ramène à sa première version" do
    apercu = texte(outil("enregistrer_page_guide", { "chapitre" => "Procédures", "titre" => "Soumettre une note de frais",
                                                    "contenu" => "## Le ticket\n\nDans le bac Admin." }))
    expect(apercu).to include("APERÇU", "CRÉER la page « Soumettre une note de frais »", "Dans le bac Admin.")
    expect(GuidePage.count).to eq(0)

    confirme("enregistrer_page_guide", { "chapitre" => "Procédures", "titre" => "Soumettre une note de frais",
                                         "contenu" => "## Le ticket\n\nDans le bac Admin." })
    page = GuidePage.sole
    expect(page.revisions.sole).to have_attributes(user: michael, source: "mcp", summary: "Création")

    lu = texte(outil("page_guide", { "page" => "soumettre une note de frais" }))
    expect(lu).to include("Page ##{page.id}", "Chapitre ##{procedures.id}", "## Le ticket", "/guide/pages/#{page.id}")

    confirme("remplacer_texte_guide", { "page" => page.id, "ancien" => "bac Admin", "nouveau" => "bac « Admin », farde au nom du membre",
                                        "motif" => "Consigne de la compta" })
    expect(page.reload.body).to include("farde au nom du membre")
    expect(page.revisions.first).to have_attributes(summary: "Consigne de la compta", source: "mcp")

    historique = texte(outil("page_guide", { "page" => page.id, "historique" => true }))
    expect(historique).to include("v2", "via Claude", "Consigne de la compta", "[actuelle]")
    expect(texte(outil("page_guide", { "page" => page.id, "version" => 1 }))).to include("Dans le bac Admin.")

    confirme("geste_page_guide", { "geste" => "restaurer", "page" => page.id, "version" => 1 })
    expect(page.reload.body).to eq("## Le ticket\n\nDans le bac Admin.")
    expect(page.revisions.count).to eq(3)
  end

  it "montre les liens vers une page et les met à jour quand elle est renommée" do
    note = GuidePage.new.tap { |p| Guide::SavePage.new(p, user: michael).call(guide_chapter_id: procedures.id, title: "Note de frais") }
    accueil = GuidePage.new.tap do |p|
      Guide::SavePage.new(p, user: michael).call(guide_chapter_id: procedures.id, title: "Accueil", body: "Voir [[Note de frais]].")
    end
    GuideScreenLink.create!(screen: "finance/expense_reports#new", label: "Nouvelle note de frais", page: note)

    expect(texte(outil("page_guide", { "page" => note.id })))
      .to include("Pages qui renvoient ici : ##{accueil.id} « Accueil »", "Écrans qui l'ouvrent (« Voir la procédure ») : Nouvelle note de frais")

    apercu = texte(outil("enregistrer_page_guide", { "page" => note.id, "titre" => "Rembourser une dépense" }))
    expect(apercu).to include("Liens [[…]] mis à jour dans 1 autre(s) page(s) : « Accueil »")
    confirme("enregistrer_page_guide", { "page" => note.id, "titre" => "Rembourser une dépense" })
    expect(accueil.reload.body).to eq("Voir [[Rembourser une dépense]].")
    expect(accueil.revisions.first.source).to eq("mcp")
  end

  it "trouve les pages par le sommaire et la recherche" do
    Guide::SavePage.new(GuidePage.new, user: michael).call(guide_chapter_id: procedures.id, title: "Fermer le gîte", body: "Couper le gaz.")

    expect(texte(outil("guide", {}))).to include("Chapitre ##{procedures.id} « Procédures »", "« Fermer le gîte »")
    expect(texte(outil("guide", { "recherche" => "gaz" }))).to include("Fermer le gîte", "Couper le gaz.")
    expect(texte(outil("guide", { "recherche" => "piscine" }))).to include("Aucune page")
  end

  it "refuse un passage introuvable ou ambigu" do
    page = GuidePage.new
    Guide::SavePage.new(page, user: michael).call(guide_chapter_id: procedures.id, title: "Clés", body: "Le bac. Le bac.")

    expect(texte(outil("remplacer_texte_guide", { "page" => page.id, "ancien" => "piscine", "nouveau" => "x" })))
      .to include("n'est pas dans la page")
    expect(texte(outil("remplacer_texte_guide", { "page" => page.id, "ancien" => "Le bac", "nouveau" => "x" })))
      .to include("revient 2 fois")
  end

  it "ajoute une image à la page et la rattache" do
    page = GuidePage.new
    Guide::SavePage.new(page, user: michael).call(guide_chapter_id: procedures.id, title: "Tickets", body: "Le bac :\n\nFin.")
    png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="

    confirme("ajouter_image_guide", { "page" => page.id, "contenu_base64" => png, "nom_fichier" => "bac-admin.png",
                                      "legende" => "Le bac Admin", "apres" => "Le bac :" })

    expect(page.reload.body).to match(%r{\ALe bac :\n\n!\[Le bac Admin\]\(/rails/active_storage/blobs/redirect/[^)]+/bac-admin\.png\)\n\nFin\.\z})
    expect(page.images.blobs.sole.filename.to_s).to eq("bac-admin.png")
    expect(texte(outil("ajouter_image_guide", { "page" => page.id, "contenu_base64" => Base64.strict_encode64("pas une image"),
                                                "nom_fichier" => "x.png" }))).to include("n'est pas une image")
  end

  it "crée, range et supprime un chapitre" do
    confirme("enregistrer_chapitre_guide", { "titre" => "Arriver aux 4 Sources", "introduction" => "Pour les nouveaux", "position" => 1 })
    arriver = GuideChapter.find_by!(title: "Arriver aux 4 Sources")
    expect(GuideChapter.ordered.to_a).to eq([arriver, procedures])

    expect(texte(outil("enregistrer_chapitre_guide", { "chapitre" => arriver.id, "supprimer" => true, "motif" => "doublon" })))
      .to include("SUPPRIMER")
    Guide::SavePage.new(GuidePage.new, user: michael).call(guide_chapter_id: arriver.id, title: "Les clés")
    expect(texte(outil("enregistrer_chapitre_guide", { "chapitre" => arriver.id, "supprimer" => true, "motif" => "doublon" })))
      .to include("encore 1 page")
  end

  it "laisse lire, mais pas écrire, un compte qui n'écrit pas dans le Guide" do
    kid = User.create!(email: "kid@les4sources.be", password: "secret123456", access_roles: %w[kid])
    serveur = described_class.new(user: kid)

    expect(outil("guide", {}, serveur: serveur)[:isError]).to be(false)
    refus = outil("enregistrer_chapitre_guide", { "titre" => "Pirate" }, serveur: serveur)
    expect(refus[:isError]).to be(true)
    expect(texte(refus)).to include("Seuls les Sourciers")
  end
end
