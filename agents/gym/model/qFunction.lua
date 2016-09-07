local function model(numInputs, numOutputs, agent)
	local function getStateMinsAndScaling(agent)
		local nbStates = agent.envDetails.nbStates
		local stateMins = agent.envDetails.stateSpec.low
		local stateScalingFactor = {}
		for i = 1, nbStates do
			if agent.envDetails.stateSpec.low[i] and agent.envDetails.stateSpec.high[i] then
            stateScalingFactor[i] = (agent.envDetails.stateSpec.high[i] - agent.envDetails.stateSpec.low[i]) / agent.numTilings
         else
            stateScalingFactor[i] = 1/agent.numTilings
         end
		end
		return stateScalingFactor, stateMins
	end
	agent.stateScalingFactor, agent.stateMins = getStateMinsAndScaling(agent)
	agent.memorySize = agent.numTiles * agent.numTiles
	local tcOpt = {
      numTilings = agent.numTilings,
      memorySize = agent.memorySize,
      scaleFactor = agent.stateScalingFactor,
      stateMins = agent.stateMins
   }
   local tc = require '../../../util/tilecoding'(tcOpt)
   local nbActions = agent.envDetails.nbActions
   local w = torch.FloatTensor(tcOpt.numTilings * tcOpt.memorySize * nbActions):zero():fill(agent.initialWeightVal)
   local e = torch.FloatTensor(tcOpt.numTilings * tcOpt.memorySize * nbActions):zero()
   Q = {}
   Q.w = w
   Q.e = e
   function Q.accumulateEligibility(state, action)
      local featIdx = Q.getFeatures(state, action)
      -- accumulate eligibility for all features present in s,a
      for idx = 1, #featIdx do
         if agent.traceType == 'replacing' then
            Q.e[featIdx[idx]] = 1
         elseif agent.traceType == 'accumulating' then
            Q.e[featIdx[idx]] = Q.e[featIdx[idx]] + 1
         end
      end
   end
   function Q.resetEligibility()
      return Q.e:fill(0)
   end
	function Q.observe(state)
      -- featurize the state with the given tilecoder
		return tc.feature(state)
   end
   function Q.getFeatures(state, action)
      -- get features indecies of Q(s,a) given state and action
      local obsv = Q.observe(state)
      local featIdx = {}
      for tiling = 1,tcOpt.numTilings do
         featIdx[tiling] = obsv[tiling] + (action * tcOpt.numTilings * tcOpt.memorySize) + 1
      end
      return featIdx
   end
   function Q.estimateQ(state, action)
      -- sum weights for Q(s,a) for single action
      local featIdx = Q.getFeatures(state, action)
		local weightSum = 0
      for idx = 1, #featIdx do
         weightSum = weightSum + Q.w[featIdx[idx]]
      end
      return weightSum
   end
   function Q.estimateAllQ(state)
      -- estimate Q(s,a) for all actions
      local qVals = torch.Tensor(nbActions):zero()
      for a = 0, nbActions-1 do
         qVals[a+1] = Q.estimateQ(state, a)
      end
      return qVals
   end
	return Q
end
return model