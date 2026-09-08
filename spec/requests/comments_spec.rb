require "rails_helper"

# Epic #242, phase 1 — le contrôleur des commentaires : Turbo Stream, liste
# blanche des types commentables, et « seulement les miens ».
RSpec.describe "Commentaires", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)  { User.create!(email: "michael@les4sources.be", password: "password123") }
  let(:other) do
    User.create!(email: "stephanie@les4sources.be", password: "password123",
                 human: Human.create!(name: "Stéphanie"))
  end
  let(:gathering) do
    Gathering.create!(name: "Réunion du collectif",
                      gathering_category: GatheringCategory.create!(name: "Collectif", color: "emerald"),
                      starts_at: Time.current, ends_at: 1.hour.from_now)
  end
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }

  before { sign_in user }

  def create_params(overrides = {})
    { comment: { commentable_type: "Gathering", commentable_id: gathering.id,
                 body: "Il manque le ticket du 12/08." }.merge(overrides) }
  end

  describe "POST /comments" do
    it "ajoute le commentaire et renvoie le fil entier en Turbo Stream" do
      expect { post comments_path, params: create_params, headers: turbo }
        .to change(Comment, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include(Comment.thread_dom_id(gathering))
      expect(response.body).to include("Il manque le ticket du 12/08.")
      expect(Comment.last.author).to eq(user)
    end

    it "refuse un corps vide et renvoie le fil avec l'erreur" do
      expect { post comments_path, params: create_params(body: ""), headers: turbo }
        .not_to change(Comment, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("ne peut pas être vide")
    end

    it "refuse un type hors liste blanche sans jamais l'instancier" do
      post comments_path,
           params: { comment: { commentable_type: "User", commentable_id: user.id, body: "hop" } },
           headers: turbo

      expect(response).to have_http_status(:not_found)
      expect(Comment.count).to eq(0)
    end

    it "fonctionne aussi sur un séjour" do
      customer = Customer.create!(first_name: "Alice", last_name: "Martin", email: "alice@example.com")
      stay = Stay.create!(customer: customer, status: "pending")

      post comments_path,
           params: { comment: { commentable_type: "Stay", commentable_id: stay.id, body: "Groupe sympa" } },
           headers: turbo

      expect(response).to have_http_status(:ok)
      expect(stay.comments.count).to eq(1)
    end

    it "sans Turbo, revient à la page de l'objet" do
      post comments_path, params: create_params, headers: { "Referer" => gathering_path(gathering) }

      expect(response).to redirect_to(gathering_path(gathering))
    end
  end

  describe "PATCH /comments/:id" do
    let!(:comment) { Comment.create!(commentable: gathering, author: user, body: "premier jet") }

    it "met à jour le sien" do
      patch comment_path(comment), params: { comment: { body: "corrigé" } }, headers: turbo

      expect(response).to have_http_status(:ok)
      expect(comment.reload.body.to_plain_text).to eq("corrigé")
    end

    it "refuse celui d'un autre" do
      sign_in other

      patch comment_path(comment), params: { comment: { body: "détourné" } }, headers: turbo

      expect(response).to have_http_status(:forbidden)
      expect(comment.reload.body.to_plain_text).to eq("premier jet")
    end

    it "laisse un admin global intervenir sur tout le fil" do
      autre_admin = User.create!(email: "accueil@les4sources.be", password: "password123")
      sign_in autre_admin

      patch comment_path(comment), params: { comment: { body: "modéré" } }, headers: turbo

      expect(response).to have_http_status(:ok)
      expect(comment.reload.body.to_plain_text).to eq("modéré")
    end

    it "refuse un corps vide" do
      patch comment_path(comment), params: { comment: { body: "" } }, headers: turbo

      expect(response).to have_http_status(:unprocessable_entity)
      expect(comment.reload.body.to_plain_text).to eq("premier jet")
    end
  end

  describe "DELETE /comments/:id" do
    let!(:comment) { Comment.create!(commentable: gathering, author: user, body: "à retirer") }

    it "supprime le sien en douceur" do
      delete comment_path(comment), headers: turbo

      expect(response).to have_http_status(:ok)
      expect(Comment.count).to eq(0)
      expect(Comment.with_deleted { Comment.count }).to eq(1)
    end

    it "refuse celui d'un autre" do
      sign_in other

      delete comment_path(comment), headers: turbo

      expect(response).to have_http_status(:forbidden)
      expect(Comment.count).to eq(1)
    end
  end

  it "exige une session" do
    sign_out user

    post comments_path, params: create_params

    expect(response).to redirect_to(new_user_session_path)
  end

  describe "le fil sur les pages" do
    it "s'affiche en bas de la fiche d'un rassemblement" do
      Comment.create!(commentable: gathering, author: user, body: "à demain")

      get gathering_path(gathering)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(Comment.thread_dom_id(gathering))
      expect(response.body).to include("à demain")
    end

    it "s'affiche en bas de la fiche pleine page d'un séjour" do
      customer = Customer.create!(first_name: "Alice", last_name: "Martin", email: "alice@example.com")
      stay = Stay.create!(customer: customer, status: "pending")
      Comment.create!(commentable: stay, author: user, body: "acompte reçu")

      get stay_path(stay)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(Comment.thread_dom_id(stay))
      expect(response.body).to include("acompte reçu")
    end
  end
end
