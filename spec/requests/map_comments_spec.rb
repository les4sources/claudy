require "rails_helper"

# Epic #348, phase 11 — les commentaires en fil sur la carte : création
# atomique du point et de son premier message, réponse inline, résolution,
# suppression de ses propres messages, notifications.
RSpec.describe "Carte du domaine — commentaires en fil (epic #348, phase 11)", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  let(:alice) { User.create!(email: "alice-fil@les4sources.be", password: "password123") }
  let(:bob) { User.create!(email: "bob-fil@les4sources.be", password: "password123") }
  let(:carol) { User.create!(email: "carol-fil@les4sources.be", password: "password123") }
  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }
  let(:layer) { MapLayer.for_kind(:comments) }
  let(:point) do
    layer.map_features.create!(feature_kind: "comment", created_by: alice,
                               geometry: { "type" => "Point", "coordinates" => [4.9078, 50.3414] })
  end
  let(:root) { point.map_comments.create!(author: alice, body: "La clôture est cassée ici") }

  def html(body = response.body) = Nokogiri::HTML(body)

  def with_base_layer
    MapBaseLayer.create!(key: "test-layer", name: "Couche de test", min_zoom: 12, max_zoom: 20,
                         bounds: { "south" => 50.339, "west" => 4.903, "north" => 50.343, "east" => 4.912 })
  end

  it "exige une session Devise" do
    post map_comments_path, headers: turbo, params: { lat: 50.34, lng: 4.9, map_comment: { body: "Coucou" } }
    expect(MapFeature.where(feature_kind: "comment").count).to eq(0)
    expect(MapComment.count).to eq(0)
  end

  context "connecté" do
    before { sign_in bob }

    it "crée la couche Commentaires en ouvrant la carte" do
      with_base_layer
      expect { get map_path }.to change { MapLayer.where(kind: "comments").count }.from(0).to(1)
      expect(html.at_css(%([data-map-target="layerName"][data-layer-kind="comments"]))).to be_present
    end

    it "sert la fiche d'un point pas encore créé, sans rien créer" do
      expect do
        get new_map_comment_path(lat: 50.3412, lng: 4.9071)
      end.not_to change(MapFeature, :count)

      doc = html
      expect(doc.at_css(%(turbo-frame#feature_panel [data-comment-new]))).to be_present
      expect(doc.at_css(%(input[name="lat"]))["value"]).to eq("50.3412")
      expect(doc.at_css(%(textarea[name="map_comment[body]"]))).to be_present
      expect(doc.text).to include("Premier message")
    end

    describe "POST /map/comments (création atomique)" do
      it "crée le point et son premier message ensemble, et rend le fil" do
        expect do
          post map_comments_path, headers: turbo,
                                  params: { lat: "50.3412", lng: "4.9071", map_comment: { body: "Ici, un nid de frelons\nÀ surveiller" } }
        end.to change(MapFeature, :count).by(1).and change(MapComment, :count).by(1)

        feature = MapFeature.order(:id).last
        expect(feature).to have_attributes(feature_kind: "comment", map_layer_id: layer.id, created_by_id: bob.id)
        expect(feature.geometry).to eq("type" => "Point", "coordinates" => [4.9071, 50.3412])
        comment = feature.map_comments.sole
        expect(comment).to have_attributes(author_id: bob.id, parent_id: nil, body: "Ici, un nid de frelons\nÀ surveiller")

        panel = html.at_css(%([data-comment-panel]))
        expect(panel["data-feature-id"]).to eq(feature.id.to_s)
        expect(panel["data-feature-saved"]).to eq("true")
        expect(panel.at_css("[data-comment-body]").text).to eq("Ici, un nid de frelons\nÀ surveiller")
      end

      it "ne crée rien sans premier message" do
        expect do
          post map_comments_path, headers: turbo, params: { lat: "50.3412", lng: "4.9071", map_comment: { body: "  " } }
        end.not_to change(MapFeature, :count)
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Écrivez un premier message.")
      end

      it "ne crée rien sans position lisible" do
        expect do
          post map_comments_path, headers: turbo, params: { lat: "nord", lng: "4.9", map_comment: { body: "Perdu" } }
        end.not_to change(MapComment, :count)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    it "ouvre le fil d'un point au clic, dans l'ordre, avec date relative et exacte" do
      travel_to(Time.zone.local(2026, 9, 27, 14, 0)) do
        root.update_column(:created_at, 2.hours.ago)
        root.reply!(author: bob, body: "Je passe demain")

        get map_feature_path(point)

        doc = html
        messages = doc.css("[data-comment-id]")
        expect(messages.map { |li| li.at_css("[data-comment-body]").text }).to eq(["La clôture est cassée ici", "Je passe demain"])
        time = messages.first.at_css("time")
        expect(time.text.strip).to eq("il y a 2 h")
        expect(time["title"]).to eq("27 septembre 2026 à 12:00")
        # Bob ne peut supprimer que son propre message.
        expect(messages.first.at_css(%([data-comment-action="delete"]))).to be_nil
        expect(messages.last.at_css(%([data-comment-action="delete"]))).to be_present
        expect(doc.at_css(%([data-comment-action="resolve"]))).to be_present
      end
    end

    describe "réponse" do
      it "ajoute le message au fil par Turbo Stream et prévient les participants sauf l'auteur" do
        carol_reply = root.reply!(author: carol, body: "Vu aussi")
        Notification.delete_all

        expect do
          post reply_map_comment_path(carol_reply), headers: turbo, params: { map_comment: { body: "J'y vais" } }
        end.to change(MapComment, :count).by(1)

        reply = MapComment.order(:id).last
        expect(reply).to have_attributes(parent_id: root.id, author_id: bob.id, map_feature_id: point.id)
        expect(response.body).to include(%(action="append" target="#{ActionView::RecordIdentifier.dom_id(root, :messages)}"))
        expect(response.body).to include("J&#39;y vais").or include("J'y vais")

        notifications = Notification.where(kind: "map_comment")
        expect(notifications.map(&:recipient)).to contain_exactly(alice, carol)
        expect(notifications.map(&:url).uniq).to eq(["/map?feature=#{point.id}"])
        expect(notifications.map(&:actor).uniq).to eq([bob])
      end

      it "refuse une réponse vide sans rien créer" do
        root
        expect do
          post reply_map_comment_path(root), headers: turbo, params: { map_comment: { body: "" } }
        end.not_to change(MapComment, :count)
        expect(response).to have_http_status(:unprocessable_content)
        expect(Notification.where(kind: "map_comment")).to be_empty
      end
    end

    describe "résolution" do
      it "résout le fil, prévient l'auteur de la racine, puis le rouvre" do
        post resolve_map_comment_path(root), headers: turbo

        expect(root.reload.resolved_at).to be_present
        expect(html.at_css("[data-comment-resolved]")).to be_present
        expect(html.at_css(%([data-comment-action="reopen"]))).to be_present
        expect(html.at_css("[data-comment-panel]")["data-feature-saved"]).to eq("true")
        notification = Notification.find_by!(kind: "map_comment_resolved")
        expect(notification).to have_attributes(recipient_id: alice.id, actor_id: bob.id, url: "/map?feature=#{point.id}")

        post reopen_map_comment_path(root), headers: turbo
        expect(root.reload.resolved_at).to be_nil
        expect(html.at_css(%([data-comment-action="resolve"]))).to be_present
      end

      it "ne prévient personne quand l'auteur résout son propre fil" do
        sign_in alice
        post resolve_map_comment_path(root), headers: turbo
        expect(root.reload.resolved_at).to be_present
        expect(Notification.where(kind: "map_comment_resolved")).to be_empty
      end
    end

    describe "suppression" do
      it "supprime sa propre réponse (soft-delete) et la retire du fil" do
        reply = root.reply!(author: bob, body: "Oups")
        delete map_comment_path(reply), headers: turbo

        expect(response.body).to include(%(action="remove" target="#{ActionView::RecordIdentifier.dom_id(reply)}"))
        expect(MapComment.exists?(reply.id)).to be(false)
        expect(MapComment.with_deleted { MapComment.exists?(reply.id) }).to be(true)
        expect(MapFeature.exists?(point.id)).to be(true)
      end

      it "refuse de supprimer le message d'autrui (403)" do
        delete map_comment_path(root), headers: turbo
        expect(response).to have_http_status(:forbidden)
        expect(MapComment.exists?(root.id)).to be(true)
      end

      it "répond 404 pour un message déjà supprimé" do
        reply = root.reply!(author: bob, body: "Oups")
        reply.remove!
        expect { delete map_comment_path(reply), headers: turbo }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it "supprimer la racine efface le fil et le point, et le dit à la carte" do
        sign_in alice
        root.reply!(author: bob, body: "Je passe demain")

        delete map_comment_path(root), headers: turbo

        expect(MapComment.where(map_feature_id: point.id)).to be_empty
        expect(MapFeature.exists?(point.id)).to be(false)
        marker = html.at_css("[data-feature-deleted]")
        expect(marker["data-feature-deleted"]).to eq(point.id.to_s)
        expect(marker["data-layer-id"]).to eq(layer.id.to_s)
      end
    end

    it "donne à la couche la bulle de chaque point : messages et état résolu" do
      root.reply!(author: bob, body: "Je passe demain")
      root.resolve!(by: bob)

      get map_features_path(layer_id: layer.id), headers: { "Accept" => "application/json" }

      props = response.parsed_body["features"].sole["properties"]
      expect(props).to include("feature_kind" => "comment", "comments_count" => 2, "resolved" => true)
    end

    it "ouvre /map?feature=<id> sur un point de commentaire" do
      with_base_layer
      get map_path(feature: root.map_feature_id)
      expect(html.at_css("[data-controller='map']")["data-map-focus-feature-value"]).to eq(point.id.to_s)
    end
  end
end
