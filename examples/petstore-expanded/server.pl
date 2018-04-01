:- use_module(library(openapi)).
:- use_module(library(option)).
:- use_module(library(debug)).
:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(swagger_ui)).

:- http_handler(root(.),
                http_redirect(see_other, root('swagger_ui')),
                []).
:- http_handler(root('swagger.yaml'),
                http_reply_file('petstore-expanded.yaml', []),
                [id(swagger_config)]).

server(Port) :-
    http_server(dispatch,
                [ port(Port)
                ]).

dispatch(Request) :-
    openapi_dispatch(Request),
    !.
dispatch(Request) :-
    http_dispatch(Request).


:- openapi_server('petstore-expanded.yaml', []).

%! findPets(-Response, +Options) is det.
%
%  @arg Response array(Pet)
%       pet response
%  @arg Options
%       - tags(+array(string))
%         tags to filter by
%       - limit(+int32)
%         maximum number of results to return

findPets(Response, Options) :-
    option(limit(Limit), Options, 100),
    option(tags(Tags), Options, _),
    once(findnsols(Limit, Pet, find_pet(Tags, Pet), Response)).

%! addPet(+RequestBody, -Response) is det.
%
%  @arg RequestBody NewPet
%       Pet to add to the store
%  @arg Response Pet
%       pet response

addPet(RequestBody, Response) :-
    (   Tag = RequestBody.get(tag)
    ->  Tags = [Tag]
    ;   Tags = []
    ),
    assert_pet(Id, RequestBody.name, RequestBody.gender, Tags),
    pet(Id, Response).

%! deletePet(+Id, -Response) is det.
%
%  @arg Id int64
%       ID of pet to delete
%  @arg Response -
%       pet deleted

deletePet(Id, Response) :-
    catch(( delete_pet(Id),
            Response = status(204)
          ),
          error(existence_error(pet, _), _),
          no_pet(Id, Response)).

%! 'find pet by id'(+Id, -Response) is det.
%
%  @arg Id int64
%       ID of pet to fetch
%  @arg Response Pet
%       pet response

'find pet by id'(Id, Response) :-
    (   pet(Id, Response)
    ->  true
    ;   no_pet(Id, Response)
    ).

no_pet(Id, Response) :-
    format(string(Msg), "Pet ~p does not exist", [Id]),
    Response = status(404, _{code:404, message:Msg}).


		 /*******************************
		 *        IMPLEMENTATION	*
		 *******************************/

:- dynamic
    pet/4,                                      % Id, Name, Gender, Tags
    next_pet_id/1.                              % Id

new_pet_id(Id) :-
    with_mutex(pet, new_pet_id_sync(Id)).

new_pet_id_sync(Id) :-
    (   retract(next_pet_id(Id))
    ->  true
    ;   Id = 1
    ),
    Id2 is Id + 1,
    asserta(next_pet_id(Id2)).

assert_pet(Id, Name, Gender, Tags) :-
    new_pet_id(Id),
    assertz(pet(Id, Name, Gender, Tags)).

delete_pet(Id) :-
    retract(pet(Id, _, _, _)),
    !.
delete_pet(Id) :-
    existence_error(pet, Id).

pet(Id, Response) :-
    pet(Id, Name, Gender, Tags),
    (   Tags == []
    ->  Response = _{id:Id, name:Name, gender:Gender }
    ;   Tags = [Tag]
    ->  Response = _{id:Id, name:Name, gender:Gender, tag:Tag}
    ).

find_pet([], Pet) :-
    !,
    pet(_, Pet).
find_pet(Tags, Pet) :-
    pet(Id, _Name, _Gender, PetTags),
    (   member(Tag, Tags),
        memberchk(Tag, PetTags)
    ->  pet(Id, Pet)
    ).
