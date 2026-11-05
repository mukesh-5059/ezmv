i would like the billboard to show few auto scrolling movies and their billboard images. the movies are to be selected based on these critireas:
the movie should be present in new ott releases lane and in trending lane. the movie should have comedy genre
if none, then have a fallback to trending+new releases
if still none, then fallback to trending
if again none, then at last have the top 5 top rated media in that dashboard

we then display all other lanes progressively,  with an static actors lane at last which is displayed only in the tamil dashboard
the actors for that lane are stored locally, if no actors are stored locally, then call the actors endpoint for a default list of actors. we can have an option to add actors to this lane in their screen(the actor screen)
on clicking on an actor in this lane opens the actor screen for that actor(use /:tmdb_id for the screen details of a specific actor)

then we have all the other lanes with the lane title acting as a focusable and clickable header strip, clicking on this opens a grid view of all the movies offered by that lane(use pagination to laod movies progressively).
have filter options at top and a to top button(we need to design the navigations to reach these buttons on a dpad). reffer backend docs for all the filter queries supported

also for the pagination, the backend will return 100 movies per request per page, so make a single request, pass it to flutter for rendering. when crossing item 80, make an another request in background for the next batch of movies

show a clear indication if there is no more results or for the end of page 

we need to plan a way on how to display options to move to other screen and dashboards
also we need to make sure all the buttons and components are reachable and that too naturally reachable, like pressing up from a lane goes into the explore all button of that lane and up from there takes users into the next lane above it. also we need to maintain ui consistency so we need to maintain the cursor at the center of the screen as much as possible, like auto centering tha ctive lane and the active movie card, the same with actor icons

the multi screen navigation bar is at the top of the screen, pressing back when somewhere deep in the screen takes to the billboard and from there we can access the navigation buttons an pressing back again takes us out of the app
in the lanes grid, we hide the screen navigation icons, but have a clear filter and a back icon
the filter pills are in the next row and then we have a grid of movies
choosing a filter option opens a vertical strip that is anchored to the right of the screen with the options we can choose for that filter. pressing back from here closes the filter options vertical strip, pressing back forom here takes to the top of the grid if we are deep down in the grid or back to the home page, if we are already at the top of the grid.