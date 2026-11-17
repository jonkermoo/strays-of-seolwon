--!strict
-- Plain text for the menu guide (placeholder pages; the real guide comes with the menus).

return table.freeze({
	Prompt = "New here? Read the guide: finishing it gives you 100 marks, "
		.. "enough to open the Medic and Engineer.",
	Pages = table.freeze({
		"You are a Stray: a cut-off unit holding out on Seolwon.",
		"Marks are your progress. They only go up and are never spent.",
		"Marks open classes, guns, crafting and driving. Rifleman is open from the start.",
		"The server is a campaign: it keeps going, day after day. Friends can join you any time.",
		"Finish this page to collect 100 marks.",
	}),
})
