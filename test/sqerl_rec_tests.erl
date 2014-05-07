%% Copyright 2014 CHEF Software, Inc. All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%

-module(sqerl_rec_tests).

-include_lib("eunit/include/eunit.hrl").

make_name(Prefix) ->
    V = io_lib:format("~B.~B.~B", erlang:tuple_to_list(erlang:now())),
    erlang:iolist_to_binary([Prefix, V]).

statements_test_() ->
    [
     {"[kitchen, cook]",
      fun() ->
              Statements = sqerl_rec:statements([kitchen, cook]),
              [ begin
                    ?assert(is_atom(Name)),
                    ?assert(is_binary(SQL))
                end
                || {Name, SQL} <- Statements ],
              KitchenFetchAll = <<"SELECT id, name FROM kitchens ORDER BY name">>,
              ?assertEqual(KitchenFetchAll,
                           proplists:get_value(kitchen_fetch_all, Statements)),
              ?assertEqual(<<"SELECT name FROM kitchens ORDER BY name">>,
                           proplists:get_value(kitchen_test_query, Statements))
      end},

     {"[eg1]",
      fun() ->
              Statements = sqerl_rec:statements([eg1]),
              Expect = [{eg1_test, <<"SELECT * FROM eg1">>}],
              ?assertEqual(Expect, Statements)
      end}
    ].

kitchen_test_() ->
    {setup,
     fun() ->
             sqerl_test_helper:setup_db()
             , error_logger:tty(false)
     end,
     fun(_) ->
             pooler:rm_pool(sqerl),
             Apps = [pooler, epgsql, sqerl, epgsql],
             [ application:stop(A) || A <- Apps ]
     end,
     [
      ?_assertEqual([], sqerl_rec:fetch_all(kitchen)),
      ?_assertEqual([], sqerl_rec:fetch(kitchen, name, <<"none">>)),
      ?_assertEqual([], sqerl_rec:fetch_page(kitchen, <<"a">>, 1000)),
      {"insert",
       fun() ->
               {K0, Name} = make_kitchen(<<"pingpong">>),
               [K1] = sqerl_rec:insert(K0),
               validate_kitchen(Name, K1)
       end},
      {"insert, fetch, update, fetch",
       fun() ->
               {K0, Name0} = make_kitchen(<<"pingpong">>),
               [K1] = sqerl_rec:insert(K0),
               [FK1] = sqerl_rec:fetch(kitchen, name, Name0),
               %% can fetch inserted
               ?assertEqual(K1, FK1),

               K2 = kitchen:'#set-'([{name, <<"tennis">>}], K1),
               ?assertEqual(ok, sqerl_rec:update(K2)),
               ?assertEqual(K2,
                            hd(sqerl_rec:fetch(kitchen, name, <<"tennis">>)))
       end},
      {"fetch_all, delete",
       fun() ->
               %% TODO: if you provide a bad atom here, you get a
               %% confusing crash. Try: 'kitchens'
               Kitchens = sqerl_rec:fetch_all(kitchen),
               ?assertEqual(2, length(Kitchens)),
               Res = [ sqerl_rec:delete(K, id) || K <- Kitchens ],
               ?assertEqual([ok, ok], Res),
               ?assertEqual([], sqerl_rec:fetch_all(kitchen))
       end},
      
      {"fetch_all, fetch_page",
       fun() ->
               %% setup
               Kitchens = [ begin
                                B = int_to_0bin(I),
                                {K, _Name} = make_kitchen(<<"A-", B/binary, "-">>),
                                K
                            end
                            || I <- lists:seq(1, 20) ],
               [ sqerl_rec:insert(K) || K <- Kitchens ],

               All = sqerl_rec:fetch_all(kitchen),
               ExpectNames = [ kitchen:'#get-'(name, K) || K <- Kitchens ],
               FoundNames = [ kitchen:'#get-'(name, K) || K <- All ],
               ?assertEqual(ExpectNames, FoundNames),

               K_1_10 = sqerl_rec:fetch_page(kitchen, sqerl_rec:first_page(), 10),
               Next = kitchen:'#get-'(name, lists:last(K_1_10)),
               K_11_20 = sqerl_rec:fetch_page(kitchen, Next , 10),
               PageNames = [ kitchen:'#get-'(name, K) || K <- (K_1_10 ++ K_11_20) ],
               ?assertEqual(ExpectNames, PageNames)
       end}
     ]}.

int_to_0bin(I) ->
    erlang:iolist_to_binary(io_lib:format("~5.10.0B", [I])).

make_kitchen(Prefix) ->
    Name = make_name(Prefix),
    K = kitchen:'#fromlist-kitchen'([{name, Name}]),
    {K, Name}.
    
validate_kitchen(Name, K) ->
    ?assert(kitchen:'#is_record-'(kitchen, K)),
    ?assertEqual(Name, kitchen:'#get-kitchen'(name, K)),
    ?assert(erlang:is_integer(kitchen:'#get-kitchen'(id, K))).

gen_fetch_by_test_() ->
    Tests = [
             {{kitchen, name},
              ["SELECT ",
               "id, name",
               " FROM ", "kitchens",
               " WHERE ", "name", " = $1"]},

             {{kitchen, id},
              ["SELECT ",
               "id, name",
               " FROM ", "kitchens",
               " WHERE ", "id", " = $1"]}
            ],
    [ ?_assertEqual(E, sqerl_rec:gen_fetch_by(Rec, By))
      || {{Rec, By}, E} <- Tests ].

gen_delete_test() ->
    Expect = ["DELETE FROM ", "kitchens",
              " WHERE ", "id", " = $1"],
    ?assertEqual(Expect, sqerl_rec:gen_delete(kitchen, id)).

gen_params_test_() ->
    Tests = [{1, "$1"},
             {2, "$1, $2"},
             {3, "$1, $2, $3"}],
    [ ?_assertEqual(E, sqerl_rec:gen_params(N))
      || {N, E} <- Tests ].

gen_update_test() ->
    Expect = ["UPDATE ", "cookers",
              " SET ",
              "name = $1, auth_token = $2, ssh_pub_key = $3, "
              "first_name = $4, last_name = $5, email = $6",
              " WHERE ", "id", " = ", "$7"],
    ?assertEqual(Expect, sqerl_rec:gen_update(cook, id)).

gen_insert_test() ->
    Expect = ["INSERT INTO ", "cookers", "(",
              "kitchen_id, name, auth_token, ssh_pub_key, "
              "first_name, last_name, email",
              ") VALUES (",
              "$1, $2, $3, $4, $5, $6, $7", ") RETURNING ",
              "id, kitchen_id, name, auth_token, auth_token_bday, "
              "ssh_pub_key, "
              "first_name, last_name, email"],
    ?assertEqual(Expect, sqerl_rec:gen_insert(cook)).

gen_fetch_all_test() ->
    Expect = ["SELECT ",
              "id, kitchen_id, name, auth_token, "
              "auth_token_bday, ssh_pub_key, first_name, "
              "last_name, email",
              " FROM ", "cookers",
              " ORDER BY ", "name"],
    ?assertEqual(Expect, sqerl_rec:gen_fetch_all(cook, name)).

gen_fetch_page_test() ->
    Expect = ["SELECT ",
              "id, kitchen_id, name, auth_token, "
              "auth_token_bday, ssh_pub_key, first_name, "
              "last_name, email",
              " FROM ", "cookers",
              " WHERE ", "name", " > $1 ORDER BY ",
              "name", " LIMIT $2"],
    ?assertEqual(Expect, sqerl_rec:gen_fetch_page(cook, name)).

pluralize_test_() ->
    [ ?_assertEqual(Expect, sqerl_rec:pluralize(In))
      || {In, Expect} <- [{"cook", "cooks"},
                          {"box", "boxes"},
                          {"batch", "batches"},
                          {"bash", "bashes"},
                          {"mess", "messes"},
                          {"entry", "entries"},
                          {"toy", "toys"},
                          {"bay", "bays"},
                          {"queue", "queues"},
                          {"node", "nodes"},
                          {"alias", "aliases"},
                          {"status", "statuses"}]
    ].