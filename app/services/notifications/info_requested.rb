module Notifications
  # « La comptabilité te demande une info » (epic #242, phase 3).
  #
  # Une note de frais bloquée parce qu'il manque un ticket, ou parce que le
  # montant ne colle pas, reste bloquée tant que personne ne le DIT. Le bouton
  # « Demander une info » pose un commentaire et déclenche cette notification —
  # le commentaire seul se noierait dans le fil.
  #
  # `Notifications::CommentPosted` prévient déjà les participants du fil. Ici on
  # vise explicitement le BÉNÉFICIAIRE, celui à qui la question est posée, avec
  # un titre qui dit qu'on attend quelque chose de lui.
  class InfoRequested
    def initialize(comment)
      @comment = comment
    end

    def self.call(comment) = new(comment).call

    def call
      report = @comment.commentable
      return nil unless report.is_a?(ExpenseReport)

      recipient = report.human&.user
      return nil if recipient.blank?

      Notify.new(
        recipient: recipient,
        actor: @comment.author,
        kind: "info_requested",
        title: "Information demandée — #{report.label}",
        body: excerpt,
        url: report.comment_path,
        notifiable: report
      ).tap(&:run).notification
    end

    private

    def excerpt
      @comment.body.to_plain_text.to_s.squish.truncate(200, separator: " ")
    end
  end
end
