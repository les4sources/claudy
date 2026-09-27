# Les fils de commentaires de la carte (epic #348, phase 11) : la date d'un
# message, lisible d'un coup d'œil (« il y a 2 h »), et les initiales qui
# tiennent lieu d'avatar.
module MapCommentsHelper
  def map_comment_relative_time(time, now: Time.current)
    seconds = (now - time).to_i
    if seconds < 60 then "à l'instant"
    elsif seconds < 3600 then "il y a #{seconds / 60} min"
    elsif seconds < 86_400 then "il y a #{seconds / 3600} h"
    elsif seconds < 7 * 86_400 then "il y a #{seconds / 86_400} j"
    else I18n.l(time.to_date, format: :long)
    end
  end

  # « 27 septembre 2026 à 14:05 » : l'infobulle de la date relative.
  def map_comment_exact_time(time)
    "#{I18n.l(time.to_date, format: :long)} à #{time.strftime('%H:%M')}"
  end

  # « Marie Dupont » → « MD » ; une adresse email → sa première lettre.
  def map_comment_initials(user)
    name = user&.display_name.to_s
    words = name.include?("@") ? [name] : name.split(/\s+/)
    words.reject(&:blank?).first(2).map { |word| word[0].upcase }.join.presence || "?"
  end
end
