#ifndef UNITY_SDF_UTIL_HLSL
#define UNITY_SDF_UTIL_HLSL


float SampleSDF(Texture3D t, SamplerState s, float3 coords, float level = 0.0f)
{
	return t.Sample(s, coords, level).x;
	//return SampleTexture(s, coords, level).x;
}

float3 SampleSDFDerivativesFast(Texture3D t, SamplerState s, float3 coords, float dist, float level = 0.0f)
{
	float3 d;
	// 3 taps
	const float kStep = 0.01f;
	d.x = SampleSDF(t, s, coords + float3(kStep, 0, 0));
	d.y = SampleSDF(t, s, coords + float3(0, kStep, 0));
	d.z = SampleSDF(t, s, coords + float3(0, 0, kStep));
	return d - dist;
}

float3 SampleSDFDerivatives(Texture3D t, SamplerState s, float3 coords, float level = 0.0f)
{
	float3 d;
	// 6 taps
	const float kStep = 0.01f;
	d.x = SampleSDF(t, s, coords + float3(kStep, 0, 0)) - SampleSDF(t, s, coords - float3(kStep, 0, 0));
	d.y = SampleSDF(t, s, coords + float3(0, kStep, 0)) - SampleSDF(t, s, coords - float3(0, kStep, 0));
	d.z = SampleSDF(t, s, coords + float3(0, 0, kStep)) - SampleSDF(t, s, coords - float3(0, 0, kStep));
	return d;
}

float GetDistanceFromSDF(Texture3D t, SamplerState s, float3 uvw, float3 extents, float level = 0.0f)
{
	float3 projUVW = saturate(uvw);
	float scalingFactor = max(extents.x, max(extents.y, extents.z));
	float dist = SampleSDF(t, s, projUVW, level) * scalingFactor;
	float3 absPos = abs(uvw - 0.5f);
	float outsideDist = max(absPos.x, max(absPos.y, absPos.z));
	if (outsideDist > 0.5f) // Check whether point is outside the box
	{
		float extraDist = length(extents * (uvw - projUVW));
		dist += extraDist;
	}
	return dist;
}

//Computes the normal of the SDF in the texture space.
float3 GetNormalFromSDF(Texture3D t, SamplerState s, float3 uvw, float level = 0.0f)
{
	float3 projUVW = saturate(uvw);
	float dist = SampleSDF(t, s, projUVW, level);
	float3 absPos = abs(uvw - 0.5f);
	float outsideDist = max(absPos.x, max(absPos.y, absPos.z));
	float3 normal;
	if (outsideDist > 0.5f) // Check whether point is outside the box
	{
		normal = normalize(uvw - 0.5f);
	}
	else
	{
		// compute normal
		float3 dir = SampleSDFDerivatives(t, s, projUVW, level);
		if (dist < 0)
			dir = -dir;
		normal = normalize(dir);
	}
	return normal;
}

#endif
