module Test where

import Harm
import Harm.Extra
import Control.Monad

main :: IO ()
main = do
    (start, t) <- elfText "../test/nix-results/test.busybox/busybox"
    forM_ (zip [start, start + 4..] t) $ \(offset, w) -> do
        putStrLn $ hex offset ++ "  " ++
            case encodingOf w of
                Nothing -> hex w
                Just enc -> show enc
