class_name TemplateResolver


static func resolve(template: String, context: Dictionary) -> String:
	var result := template
	for key in context:
		result = result.replace("{" + str(key) + "}", str(context[key]))
	return result
