function opts = prepareNUFFT(N,np,trajectory,viewOrder,varargin)
% PREPARENUFFT Creates the options structure for gridding non-Cartesian k-space
% with the NUFFT.
%
% INPUTS
% N [1x1] -> image size
% trajectory [string]   -> 'radial', 'spiral'
% viewOrder [string]    -> 'linear_sorted','goldenAngle_180','goldenAngle_sorted_180','goldenAngle_360','goldenAngle_sorted_360'
% optional arguments should be input as string-value pairs
	% fov [1x1]                 -> field of view (mm2)
	% correctionFactor [1x1]    -> raises the density compensation to a power (default is 1)
	% readShift [1x1]           -> read offset in k-space
	% phaseShift [1x1]          -> phase offset in k-space
% 
% OUTPUT
% opts [structure] The 'opts' structure is used by the gridding/inverse gridding functions.
% -----------------------------------------------------------------------------------------
% Jesse Hamilton
% Dec 2013
% MIMOSA Code Repository
% -----------------------------------------------------------------------------------------

opts = struct();
opts.trajectory = trajectory;
opts.viewOrder = viewOrder;
opts.interleaves = [];
opts.N = N;
opts.fov = 300; % default field-of-view is 300mm2
opts.readShift = 0;
opts.phaseShift = 0;
opts.correctionFactor =1;
opts.G = [];
opts.wib = [];
opts.kx = [];
opts.ky = [];
opts.gridReadLow = []; % smallest readout point to grid and reconstruct (for spiral)
opts.gridReadHigh = []; % largest readout point to grid and reconstruct (for spiral)

for i = 1:2:length(varargin)
	switch varargin{i}
        case 'trajname'
            trajname = varargin{i+1};
		case 'fov' 
			opts.fov = varargin{i+1};
		case 'correctionFactor'
			opts.correctionFactor = varargin{i+1};
		case 'readShift'
			opts.readShift = varargin{i+1};
		case 'phaseShift'
			opts.phaseShift = varargin{i+1};
        case 'gridLow'
            opts.gridReadLow = varargin{i+1};
        case 'gridHigh'
            opts.gridReadHigh = varargin{i+1};
        case 'interleaves'
            opts.interleaves = varargin{i+1};
        case 'kx'
            opts.kx = varargin{i+1};
        case 'ky'
            opts.ky = varargin{i+1};
		otherwise % skip it
	end
end


%% Prepare NUFFT structure
switch opts.trajectory
    case 'radial'; prepare_radial();
    case 'spiral'; prepare_spiral();
    case 'custom'; prepare_custom();
    otherwise; error('Trajectory not supported')
end

    function prepare_custom()
        if isempty(opts.kx), error('You must pass in the trajectory kx'); end
        if isempty(opts.ky), error('You must pass in the trajectory ky'); end
        
        kspace = [opts.kx(:) opts.ky(:)];
        kspace = kspace./(opts.fov);
        
        mask = true(N,N);
        maskSize = size(mask);
        
        nufft_args = {maskSize, [3 3], 2*maskSize, maskSize/2, 'table', 2^12, 'minmax:kb'};
        G = Gmri(kspace, mask, 'fov', opts.fov, 'basis', {'rect'}, 'nufft', nufft_args);
        wi = mri_density_comp(kspace,'voronoi','fix_edge',0,'G',G.arg.Gnufft);
        wib = reshape(wi,size(opts.kx));
        wib(wib>0.00005) = 0;
        wib = wib(:);
        wib = wib.^(opts.correctionFactor);
        
        opts.G = G; 
		opts.wib = wib; 
        opts.gridReadLow = 1;
        opts.gridReadHigh = size(opts.kx,1);
    end

    function prepare_spiral()
                    
        load(trajname);
        
        if isempty(opts.gridReadLow)
            opts.gridReadLow = 1;
        end
        if isempty(opts.gridReadHigh)
            opts.gridReadHigh = size(kxall,1);
        end
        
        opts.kx = kxall/max(kxall(:))*opts.N/2;
        opts.ky = kyall/max(kyall(:))*opts.N/2;
        
        kxr = opts.kx(opts.gridReadLow:opts.gridReadHigh,:);
        kyr = opts.ky(opts.gridReadLow:opts.gridReadHigh,:);
        ksp = [kxr(:) kyr(:)]/opts.fov;
        
        mask = true(opts.N,opts.N);
        sizeMask = size(mask);
        nufft_args = {sizeMask, [6 6], 2*sizeMask, sizeMask/2, 'table', 2^12, 'minmax:kb'};
        opts.G = Gmri(ksp, mask, 'fov', opts.fov, 'basis', {'dirac'}, 'nufft', nufft_args); % G forward
        
        wi = abs(mri_density_comp(ksp, 'pipe','G',opts.G.arg.Gnufft)); %another choice from Greg.
        opts.wib=reshape(wi,size(kxr));
        opts.wib(opts.wib>.000020)=0;
        opts.wib=opts.wib(:);
    end

 function prepare_radial()
        
        golden_ratio = (sqrt(5)+1)/2;
        golden_angle = 180/golden_ratio;
        
        switch opts.viewOrder
            
            case 'linear_sorted'
                ang = 0:180/np:180-180/np;
                
            case 'goldenAngle_sorted_180'
                ang = 0:golden_angle:golden_angle*(np-1);
                ang = rem(ang,180);
                ang = sort(ang);
                
            case 'goldenAngle_sorted_360'
                ang = 0:golden_angle:golden_angle*(np-1);
                ang = rem(ang,360);
                ang = sort(ang);
                
            case 'goldenAngle_180'
                ang = 0:golden_angle:golden_angle*(np-1);
                ang = rem(ang,180);
                
            case 'goldenAngle_360'
                ang = 0:golden_angle:golden_angle*(np-1);
                ang = rem(ang,360);
                
            case 'interleaved'
                temp = 0:180/np:180-180/np;
                af = opts.interleaves;
                assert(~isempty(af),'Must specify number of interleaves');
                assert(af == round(af),'Number of projections is not divisible by number of interleaves');
                ang = zeros(np/af,af);
                for u=1:af
                    ang(:,u) = temp(u:af:end);
                end
                ang = ang(:).';
                
            otherwise
                error('View ordering scheme not supported')
        end
        
        li = -N/2 : 0.5 : N/2-0.5;
        ky = li'*sind(ang);
        kx = li'*cosd(ang);
        
        kspace = [kx(:) ky(:)];
        kspace = kspace./(opts.fov);
        
        mask = true(N,N);
        maskSize = size(mask);
        
        nufft_args = {maskSize, [3 3], 2*maskSize, maskSize/2, 'table', 2^12, 'minmax:kb'};
        G = Gmri(kspace, mask, 'fov', opts.fov, 'basis', {'rect'}, 'nufft', nufft_args);
        wi = mri_density_comp(kspace,'voronoi','fix_edge',0,'G',G.arg.Gnufft);
        wib = reshape(wi,size(kx));
        wib(wib>0.00005) = 0;
        wib = wib(:);
        wib = wib.^(opts.correctionFactor);
        
        opts.G = G; 
		opts.wib = wib; 
		opts.kx = kx; 
		opts.ky = ky;
        opts.gridReadLow = 1;
        opts.gridReadHigh = size(kx,1);
    end

end