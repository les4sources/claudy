require "rails_helper"

# Le Guide des 4 Sources (Michael, 2026-10-19) : chaque écriture d'une page
# laisse une version signée ; on sait qui a contribué et qui l'a touchée en
# dernier.
RSpec.describe GuidePage do
  let(:chloe) { User.create!(email: "chloe@les4sources.be", password: "password123", human: Human.create!(name: "Chloé")) }
  let(:seb) { User.create!(email: "seb@les4sources.be", password: "password123") }
  let(:chapitre) { GuideChapter.create!(title: "Procédures") }

  def enregistrer(page, user, attributs)
    expect(Guide::SavePage.new(page, user: user).call(attributs)).to be(true), page.errors.full_messages.to_sentence
    page
  end

  it "écrit une version à la création puis à chaque changement, jamais pour rien" do
    page = enregistrer(GuidePage.new, chloe, guide_chapter_id: chapitre.id, title: "Note de frais", body: "Étape 1")
    expect(page.revisions.size).to eq(1)
    expect(page).to have_attributes(last_editor: chloe, position: 1)

    enregistrer(page, seb, body: "Étape 1\r\n", summary: "")
    expect(page.revisions.reload.size).to eq(1)

    enregistrer(page, seb, body: "Étape 1\n\nÉtape 2", summary: "Ajout de l'étape 2")
    expect(page.revisions.reload.size).to eq(2)
    expect(page.revisions.first).to have_attributes(user: seb, summary: "Ajout de l'étape 2", source: "web")
    expect(page.reload.last_editor).to eq(seb)
    expect(page.contributors).to eq([seb, chloe])
    expect(page.revisions.first.number).to eq(2)
  end

  it "revient à une version en en créant une nouvelle" do
    page = enregistrer(GuidePage.new, chloe, guide_chapter_id: chapitre.id, title: "Coordonnées", body: "IBAN BE01")
    premiere = page.revisions.first
    enregistrer(page, chloe, body: "IBAN BE02")

    Guide::SavePage.new(page, user: seb).restore(premiere)

    expect(page.reload.body).to eq("IBAN BE01")
    expect(page.revisions.size).to eq(3)
    expect(page.revisions.first.summary).to eq("Retour à la version 1")
  end

  it "rattache à la page les images de son Markdown" do
    png = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(png), filename: "bac.png", content_type: "image/png")
    chemin = Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)

    page = enregistrer(GuidePage.new, chloe, guide_chapter_id: chapitre.id, title: "Tickets", body: "![Le bac](#{chemin})")

    expect(page.images.blobs).to eq([blob])
  end

  it "range une page déplacée à la fin de son nouveau chapitre" do
    autre = GuideChapter.create!(title: "Arriver")
    enregistrer(GuidePage.new, chloe, guide_chapter_id: autre.id, title: "Les clés")
    page = enregistrer(GuidePage.new, chloe, guide_chapter_id: chapitre.id, title: "Le badge")

    enregistrer(page, chloe, guide_chapter_id: autre.id)

    expect(page.reload).to have_attributes(chapter: autre, position: 2)
  end

  it "cherche chaque mot dans le titre ou le texte" do
    page = enregistrer(GuidePage.new, chloe, guide_chapter_id: chapitre.id, title: "Soumettre une note de frais",
                                             body: "Déposer le ticket dans le bac Admin")
    enregistrer(GuidePage.new, chloe, guide_chapter_id: chapitre.id, title: "Fermer le gîte", body: "Le bac à compost")

    expect(GuidePage.search("note bac")).to eq([page])
    expect(GuidePage.search("")).to include(page)
  end

  it "garde un chapitre qui a encore des pages" do
    enregistrer(GuidePage.new, chloe, guide_chapter_id: chapitre.id, title: "Une page")
    expect(chapitre).not_to be_removable
  end
end
