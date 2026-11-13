in the top nav bar, only the left and right arrows have use(moving from dashboards and other screen icons), the up arrow is disabled, and the down arrow on any button takes focus(both cursor and visual) to the billboard

in the billboard, only left and right have proper use, the up arrow on any movie takes to the nav bar and down takes to the continue watching lane(the movie cards)(if present) or the first lane title

when focusing on a lane title, position it in such a way so that both the movie card and the title is on the center of the screen as we wont be doing the screen centering on the movie cards

only up and down buttons work on the movie title, up for the previous lane *title* and down for that lane's movie cards.

in the list of movie cards, only left and right move within the row and up takes focus to its title, and down to the next lane title

if its the tamil dashboard, we also have the actors lane. the focus comes from the last normal lane's movie cards and directly to the profile image of the first actor/the last index the cursor was on

and in all of these there are common sense related movements like no left on the first movie card and no right on the last movie card, the same with actors lane, and top nav bar and no down in the cards of last lane if no actors lane or no down on the actors lane

in billboard we loo back to the start or end when we reach the end, but the above condition applies to it if there is only 1 element in the billboard

when we are getting focus on this screen after poping another screen, we also have to remember the last widget the cursor was on and scroll the screen so that, that widget comes into view.
