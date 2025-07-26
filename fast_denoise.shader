uniform float uSigma< // 控制模糊范围
    string label = "Sigma (spatial)";
    string widget_type = "slider";
    float minimum = 0.1;
    float maximum = 50.0;
    float step = 0.1;
> = 1.0;

uniform float uThreshold< // 控制边缘保留程度
    string label = "Color Threshold";
    string widget_type = "slider";
    float minimum = 0.01;
    float maximum = 1.0;
    float step = 0.01;
> = 0.1;
uniform texture2d previous_output;
uniform texture2d previous_image;
float4 bilateralBlur(float2 uv, float2 size, float sigma, float threshold)
{
    float4 centerColor = image.Sample(textureSampler, uv);
    float motionScore = 0.0;
    float weightSum = 0.0;
    float4 colorSum = float4(0, 0, 0, 0);

    for (int dx = -1; dx <= 1; ++dx)
    {
        for (int dy = -1; dy <= 1; ++dy)
        {
            float2 offset = float2(dx, dy) / size * sigma;
            float4 prev = previous_output.Sample(textureSampler, uv + offset);

            float4 sampleColor = (image.Sample(textureSampler, uv + offset));
            
            // 颜色差异因子
            float colorDiff = abs(dot(sampleColor.rgb,float3( 0.299,  0.587,  0.114)) - dot(centerColor.rgb,float3( 0.299,  0.587,  0.114)));
            float colorWeight = exp(-(colorDiff * colorDiff) / (2.0 * threshold * threshold));

            // 空间距离权重
            float dist2 = float(dx * dx + dy * dy);
            float spatialWeight = exp(-dist2 / (2.0 * sigma * sigma));

            float weight = spatialWeight * colorWeight;

            colorSum += sampleColor * weight;
            weightSum += weight;

            
            motionScore+=dot(sampleColor.rgb, float3(0.299, 0.587, 0.114))-dot(prev.rgb, float3(0.299, 0.587, 0.114));
        }
    }

    return float4(colorSum.rgb / weightSum,motionScore/9);
}
float getLuma(float3 rgb) {
    return dot(rgb, float3(0.299, 0.587, 0.114));
}
float2 sobelLuma(float2 uv, float2 size) {
    float sx = 0.0;
    float sy = 0.0;

    float2 offset = 1.0 / size;

    // Sobel kernels
    float2 pos[9] = {
        float2(-1, -1), float2( 0, -1), float2( 1, -1),
        float2(-1,  0), float2( 0,  0), float2( 1,  0),
        float2(-1,  1), float2( 0,  1), float2( 1,  1)
    };

    float gx[9] = { -1,  0, +1,
                    -2,  0, +2,
                    -1,  0, +1 };

    float gy[9] = { -1, -2, -1,
                     0,  0,  0,
                    +1, +2, +1 };

    for (int i = 0; i < 9; ++i) {
        float3 color = image.Sample(textureSampler, uv + pos[i] * offset).rgb;
        float lum = getLuma(color);
        sx += lum * gx[i];
        sy += lum * gy[i];
    }

    return float2(sx, sy); // fx, fy
}
float avg(float a,float b){
    return (a  + b ) * 0.5;
}
float4 median3(float4 a, float4 b) {

    return float4(
        avg(a.r,b.r),
        avg(a.g,b.g),
        avg(a.b,b.b),
        1.0
    );
}

float4 mainImage(VertData v_in) : TARGET
{
    float4 current=bilateralBlur(v_in.uv, uv_size, uSigma, uThreshold);
    // float2 grad=sobelLuma(v_in.uv, uv_size);
    float2 grad=float2(ddx(dot(current.rgb, float3(0.299, 0.587, 0.114))),ddy(dot(current.rgb, float3(0.299, 0.587, 0.114))));
    float2 normalFlow=grad*current.w/uv_size/(dot(grad,grad)+1E-4);

    float4 pre=previous_output.Sample(textureSampler,clamp(v_in.uv+normalFlow,0,1));
    float4 centerColor=image.Sample(textureSampler, v_in.uv);
    float2 v=normalFlow*0.5;
    for(float i=1;i<10;i++){
        float4 diff=abs(centerColor-pre);
        if(diff.r>0.1&&diff.g>0.1&&diff.b>0.1)
            normalFlow-=v;
        else normalFlow+=v;
        v*=0.5;
        pre=previous_output.Sample(textureSampler,clamp(v_in.uv+normalFlow,0,1));

    }
    // return lerp(centerColor,pre,0.5);
    return pre*3/7+previous_image.Sample(textureSampler,v_in.uv+normalFlow)*2/7+centerColor*2/7;
    // return float4(normalFlow.xy, 0.0, 1.0); 
}
