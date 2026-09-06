module Api
  module V1
    # Les notes du calendrier (#217) — les post-it datés que l'équipe pose sur
    # la vue partagée du Domaine.
    #
    # L'API existe pour qu'un agent puisse annoncer sur le calendrier ce qui se
    # décide ailleurs : une pizza party réservée sur la boulangerie n'atterrit
    # aujourd'hui que dans une boîte mail interne, et l'équipe apprend par
    # hasard qu'un groupe de dix-huit personnes arrive vendredi soir.
    #
    # Claudy ne sait pas ce qu'est une pizza party : il expose des notes. Le
    # texte du post-it est composé par l'appelant.
    #
    # POST est un UPSERT sur `external_ref` : rejouer le même appel met la note
    # à jour au lieu d'en poser une seconde. La réponse dit lequel des deux
    # s'est produit (`meta.created`).
    class NotesController < BaseController
      before_action :get_note, only: [:show, :update, :destroy]
      before_action :set_date_range, only: [:index]

      def index
        scope = Note.all
        scope = scope.where(date: @from..) if @from
        scope = scope.where(date: ..@to) if @to
        scope = scope.where(color: params[:color]) if params[:color].present?
        scope = scope.where(external_ref: params[:external_ref]) if params[:external_ref].present?
        scope = scope.matching(params[:q])

        @notes = paginate(scope.order(date: :desc, id: :desc))
      end

      def show; end

      def create
        attributes = note_params
        reference = attributes[:external_ref].presence
        @note = (Note.find_by(external_ref: reference) if reference) || Note.new
        @created = @note.new_record?

        if @note.update(attributes)
          render :show, status: @created ? :created : :ok
        else
          render_invalid(@note)
        end
      end

      def update
        if @note.update(note_params.except(:external_ref))
          render :show
        else
          render_invalid(@note)
        end
      end

      def destroy
        @note.soft_delete!(validate: false)
        head :no_content
      end

      private

      def get_note
        @note = Note.find(params[:id])
      end

      # `from` / `to` bornent `date`, inclusivement.
      def set_date_range
        @from = parse_date(params[:from])
        @to = parse_date(params[:to])
      rescue Date::Error
        render json: { error: "unprocessable_entity", message: "Paramètres `from`/`to` invalides : attendu AAAA-MM-JJ." },
               status: :unprocessable_entity
      end

      def parse_date(value)
        Date.parse(value) if value.present?
      end

      def note_params
        params.require(:note).permit(:body, :date, :color, :external_ref)
      end
    end
  end
end
