module Main where

import Control.Exception (throw)
import Control.Monad (void)
import Data.Dynamic
import Data.Time.Clock (picosecondsToDiffTime)

-- imports from io-sim, io-sim-classes, contra-tracer
import Control.Tracer
import Control.Monad.IOSim
import Control.Monad.Class.MonadTime
import Control.Monad.Class.MonadAsync
import Control.Monad.Class.MonadSTM
import Control.Monad.Class.MonadFork
import Control.Monad.Class.MonadTimer
import Control.Monad.Class.MonadSay

-- imports from this package
import Channel
import HeadNode
import HeadNode.Types
import MSig.Mock
import Tx.Mock

dynamicTracer :: Typeable a => Tracer (SimM s) a
dynamicTracer = Tracer traceM

selectTraceHydraEvents
  :: Trace a -> [(Time, ThreadId (SimM s), TraceHydraEvent MockTx)]
selectTraceHydraEvents = go
  where
    go (Trace t tid _ (EventLog e) trace)
     | Just x <- fromDynamic e    = (t,tid,x) : go trace
    go (Trace _ _ _ _ trace)      =         go trace
    go (TraceMainException _ e _) = throw e
    go (TraceDeadlock      _   _) = [] -- expected result in many cases
    go (TraceMainReturn    _ _ _) = []

main :: IO ()
main = do
  let tracer = dynamicTracer
  let trace = runSimTrace (twoNodesExample tracer)
  putStrLn "full trace: "
  print trace
  putStrLn "trace of TraceProtocolEvent:"
  print $ selectTraceHydraEvents trace


twoNodesExample :: (MonadTimer m, MonadSTM m, MonadSay m, MonadFork m, MonadAsync m)
  => Tracer m (TraceHydraEvent MockTx)
  -> m ()
twoNodesExample tracer = do
  node0 <- newNode $ simpleNodeConf 2 0
  node1 <- newNode $ simpleNodeConf 2 1
  connectNodes simpleChannels node0 node1
  void $ concurrently (startNode tracer node0) (startNode tracer node1)
  where
    simpleChannels = createConnectedBoundedChannels 100

threeNodesExample :: (MonadTimer m, MonadSTM m, MonadSay m, MonadFork m, MonadAsync m)
  => Tracer m (TraceHydraEvent MockTx)
  -> m ()
threeNodesExample tracer = do
  node0 <- newNode $ simpleNodeConf 3 0
  node1 <- newNode $ simpleNodeConf 3 1
  node2 <- newNode $ simpleNodeConf 3 2
  connectNodes simpleChannels node0 node1
  connectNodes simpleChannels node0 node2
  connectNodes simpleChannels node1 node2
  void $ concurrently (startNode tracer node0) $
    concurrently (startNode tracer node1) (startNode tracer node2)
  where
    simpleChannels = createConnectedBoundedChannels 100

simpleMsig :: MS MockTx
simpleMsig = MS {
  ms_sig_tx = ms_sign_delayed (millisecondsToDiffTime 2),
  ms_asig_tx = ms_asig_delayed (millisecondsToDiffTime 5),
  ms_verify_tx = ms_verify_delayed (millisecondsToDiffTime 7),

  ms_sig_sn = ms_sign_delayed (millisecondsToDiffTime 2),
  ms_asig_sn = ms_asig_delayed (millisecondsToDiffTime 5),
  ms_verify_sn = ms_verify_delayed (millisecondsToDiffTime 7)
}

-- | Node that sends just one transaction. Snapshots are created round-robin.
simpleNodeConf
  :: Int -- ^ Total number of nodes
  -> Int -- ^ This node number
  -> NodeConf MockTx
simpleNodeConf n i
  | n <= i = error "simpleNodeConf: Node index must be smaller than total number of nodes."
  | otherwise = NodeConf {
      hcNodeId = NodeId i,
      hcTxSendStrategy = SendSingleTx (MockTx (TxId i) (millisecondsToDiffTime 1)),
      hcMSig = simpleMsig,
      hcLeaderFun = \(SnapN s) -> NodeId (s `mod` n)
      }

millisecondsToDiffTime :: Integer -> DiffTime
millisecondsToDiffTime = picosecondsToDiffTime . (* 1000000000)
