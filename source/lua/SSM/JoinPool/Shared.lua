-- Join Pool - network messages (server and client register them in the same order).
--
-- SSM_JoinPoolQueue: the client ids of everyone in the pool, as ",5,12,", sent to everyone when
-- the pool changes and every few seconds, so the scoreboard can label them.
-- SSM_JoinPoolAttention: sent to the two players asked to type !readyq, to flash their window.

Shared.RegisterNetworkMessage("SSM_JoinPoolQueue", { clients = "string (512)" })
Shared.RegisterNetworkMessage("SSM_JoinPoolAttention", { seconds = "integer (0 to 255)" })
