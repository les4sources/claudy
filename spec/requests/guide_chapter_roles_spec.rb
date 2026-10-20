require "rails_helper"

# Les chapitres du Guide par rôle (Michael, 2026-10-19) : chaque chapitre dit
# quels rôles le lisent, les Sourciers lisent tout, et un compte restreint à
# ses activités y est porteur·euse.
RSpec.describe "Chapitres du Guide par rôle", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:sourcier) { User.create!(email: "michael@les4sources.be", password: "password123", access_roles: %w[sourcier]) }
  let(:kid) { User.create!(email: "kid@les4sources.be", password: "password123", access_roles: %w[kid]) }
  # Sourcier sur le papier, comme les comptes d'avant les rôles : restreint, il
  # ne lit que ce qui est ouvert aux porteurs.
  let(:porteur) do
    User.create!(email: "bene@les4sources.be", password: "password123", access_roles: %w[sourcier],
                 restricted_to_experiences: true)
  end

  let!(:collectif) { GuideChapter.create!(title: "Petits comptes entre Sourciers", access_roles: %w[administratif]) }
  let!(:activites) { GuideChapter.create!(title: "Porter une activité", access_roles: %w[porteur kid]) }

  def page_dans(chapitre, titre, body = "")
    GuidePage.new.tap do |page|
      Guide::SavePage.new(page, user: sourcier).call(guide_chapter_id: chapitre.id, title: titre, body: body)
    end
  end

  let!(:note) { page_dans(collectif, "Rentrer une note de frais", "Le ticket va dans le bac Admin.") }
  let!(:creneaux) { page_dans(activites, "Ouvrir ses créneaux", "Voir aussi [[Rentrer une note de frais]].") }

  it "ouvre un nouveau chapitre à tous les rôles sauf aux porteurs" do
    expect(GuideChapter.new.access_roles).to match_array(%w[communication kid administratif anier])
  end

  it "ne montre à un rôle que ses chapitres : sommaire, recherche, pages et historique" do
    sign_in kid

    get guide_root_path
    expect(response.body).to include("Porter une activité", "Ouvrir ses créneaux")
    expect(response.body).not_to include("Petits comptes", "Rentrer une note de frais")

    get guide_root_path(q: "ticket")
    expect(response.body).to include("Rien ne correspond")

    get guide_page_path(note)
    expect(response).to redirect_to(guide_root_path)
    get guide_page_revisions_path(note)
    expect(response).to redirect_to(guide_root_path)

    # Le lien vers une page fermée n'en est plus un.
    get guide_page_path(creneaux)
    expect(response.body).to include("Rentrer une note de frais")
    expect(response.body).not_to include(guide_page_path(note))
  end

  it "laisse un compte restreint à ses activités lire les chapitres des porteurs, et rien d'autre" do
    sign_in porteur

    get guide_root_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Ouvrir ses créneaux")
    expect(response.body).not_to include("Rentrer une note de frais", new_guide_page_path)

    get guide_page_path(creneaux)
    expect(response).to have_http_status(:ok)
    get guide_page_revisions_path(creneaux)
    expect(response).to have_http_status(:ok)

    get guide_page_path(note)
    expect(response).to redirect_to(guide_root_path)

    # Il n'écrit jamais, même Sourcier sur le papier.
    get edit_guide_page_path(creneaux)
    expect(response).to redirect_to(experiences_path)
    patch guide_page_path(creneaux), params: { guide_page: { body: "Piraté" } }
    expect(creneaux.reload.body).not_to eq("Piraté")
  end

  it "montre le Guide dans la barre d'un porteur seulement quand un chapitre lui est ouvert" do
    sign_in porteur
    get experiences_path
    expect(response.body).to include(%(href="#{guide_root_path}"))

    activites.update!(access_roles: %w[kid])
    get experiences_path
    expect(response.body).not_to include(%(href="#{guide_root_path}"))
  end

  it "laisse le Sourcier tout lire, même un chapitre décoché pour tous" do
    collectif.update!(access_roles: [])
    sign_in sourcier

    get guide_root_path
    expect(response.body).to include("Rentrer une note de frais", "Lu par les Sourciers seulement",
                                     "Lu par les Sourciers et : Kid, Porteur·euse")
    get guide_page_path(note)
    expect(response).to have_http_status(:ok)
  end

  it "règle les rôles d'un chapitre depuis son formulaire" do
    sign_in sourcier

    patch guide_chapter_path(collectif), params: { guide_chapter: { title: collectif.title, access_roles: ["", "kid", "pirate"] } }
    expect(collectif.reload.access_roles).to eq(%w[kid])

    post guide_chapters_path, params: { guide_chapter: { title: "Informatique", access_roles: [""] } }
    expect(GuideChapter.find_by!(title: "Informatique").access_roles).to eq([])
  end

  describe "Paramètres › Accès" do
    it "règle, pour chaque rôle, les chapitres qu'il lit" do
      sign_in sourcier

      get access_roles_path
      expect(response.body).to include("Le Guide, par rôle", "Petits comptes entre Sourciers")

      patch access_guide_chapters_path, params: { chapters: { collectif.id.to_s => ["", "communication", "porteur"],
                                                              activites.id.to_s => [""] } }
      expect(response).to redirect_to(access_roles_path(anchor: "guide"))
      expect(collectif.reload.access_roles).to match_array(%w[communication porteur])
      expect(activites.reload.access_roles).to eq([])
    end

    it "est réservé aux Sourciers" do
      sign_in kid
      patch access_guide_chapters_path, params: { chapters: { collectif.id.to_s => %w[kid] } }
      expect(collectif.reload.access_roles).to eq(%w[administratif])
    end
  end

  describe "« Voir la procédure »" do
    it "ne renvoie pas à une page d'un chapitre fermé" do
      GuideScreenLink.create!(screen: "experiences#index", path: experiences_path, page: note, user: sourcier)
      communication = User.create!(email: "com@les4sources.be", password: "password123", access_roles: %w[communication])
      sign_in communication

      get experiences_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Voir la procédure")

      collectif.update!(access_roles: %w[communication])
      get experiences_path
      expect(response.body).to include("Voir la procédure")
    end
  end
end
