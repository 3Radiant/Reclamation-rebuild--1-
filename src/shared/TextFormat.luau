--[[
	TextFormat (shared) - safe rich text for chat and thoughts.

	  *text*      -> italic
	  **text**    -> bold
	  ***text***  -> bold + italic

	ALWAYS use TextFormat.format(rawText): it escapes the player's text first so they
	can't inject their own <font>/<stroke>/<img> tags, THEN applies the asterisk rules.
]]

local TextFormat = {}

function TextFormat.escape(text: string): string
	text = text:gsub("&", "&amp;")
	text = text:gsub("<", "&lt;")
	text = text:gsub(">", "&gt;")
	text = text:gsub('"', "&quot;")
	text = text:gsub("'", "&apos;")
	return text
end

-- Expects text that is ALREADY escaped. Longest markers first.
function TextFormat.markdown(escaped: string): string
	escaped = escaped:gsub("%*%*%*([^%*]+)%*%*%*", "<b><i>%1</i></b>")
	escaped = escaped:gsub("%*%*([^%*]+)%*%*", "<b>%1</b>")
	escaped = escaped:gsub("%*([^%*]+)%*", "<i>%1</i>")
	return escaped
end

function TextFormat.format(raw: string): string
	return TextFormat.markdown(TextFormat.escape(raw))
end

return TextFormat
