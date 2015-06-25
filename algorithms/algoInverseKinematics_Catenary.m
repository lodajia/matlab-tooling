function [length, varargout] = algoInverseKinematics_Catenary(Pose, PulleyPositions, CableAttachments, Wrench, CableForceLimits, CableProperties, GravityConstant)
% ALGOINVERSEKINEMATICS_CATENARY - Perform inverse kinematics for the given
%   pose of the virtual robot using catenary lines
%   Inverse kinematics means to determine the values for the joint
%   variables (in this case cable lengths) for a given endeffector pose.
%   This is quite a simple setup for cable-driven parallel robots because
%   the equation for the kinematic loop has to be solved, which is the sole
%   purpose of this method.
%   It can determine the cable lengths for any given robot configuration
%   (note that calculations will be done as if we were looking at a 3D/6DOF
%   cable robot following necessary conventions, so adjust your variables
%   accordingly). To determine the cable lengths, both the simple kinematic
%   loop can be used as well as the advanced pulley kinematics (considering
%   pulley radius and rotatability).
% 
%   LENGTH = ALGOINVERSEKINEMATICS_PULLEY(POSE, PULLEYPOSITIONS, CABLEATTACHMENTS)
%   performs simple inverse kinematics with the cables running from a_i to
%   b_i for the given pose
% 
%   [LENGTH, CABLEVECTORS] = ALGOINVERSEKINEMATICS_PULLEY(...) also provides the
%   vectors of the cable directions from platform to attachment point given
%   in the global coordinate system
% 
%   [LENGTH, CABLEVECTORS, CABLEUNITVECTORS] = ALGOINVERSEKINEMATICS_PULLEY(...)
%   also provides the unit vectors for each cable which might come in handy
%   at times
%   
%   Inputs:
%   
%   POSE: The current robots pose given as a 12-column row vector that has
%   the [x, y, z] position in the first three entries and then follwing are
%   the entries of the rotation matrix such that the vector POSE looks
%   something like this
%   pose = [x, y, z, R11, R12, R13, R21, R22, R23, R31, R32, R33]
% 
%   PULLEYPOSITIONS: Matrix of pulley positions w.r.t. the world frame. Each
%   pulley has its own column and the rows are the x, y, and z-value,
%   respectively i.e., PULLEYPOSITIONS must be a matrix of 3xM values. The
%   number of pulleyes i.e., N, must match the number of cable attachment
%   points in CABLEATTACHMENTS (i.e., its column count) and the order must
%   mach the real linkage of pulley to cable attachment on the platform
% 
%   CABLEATTACHMENTS: Matrix of cable attachment points w.r.t. the
%   platforms coordinate system. Each attachment point has its own column
%   and the rows are the x, y, and z-value, respectively, i.e.,
%   CABLEATTACHMENTS must be a matrix of 3xM values. The number of cables
%   i.e., N, must match the number of pulleyes in PULLEYPOSITIONS (i.e., its
%   column count) and the order must match the real linkage of cable
%   attachment on the platform to pulley.
% 
%   Outputs:
% 
%   LENGTH: Length is a vector of size 1xM with the cable lengths
%   determined using either simple or advanced kinematics
%
%   CABLEVECTOR: Vectors of each cable from attachment point to corrected
%   pulley point given as 3xM matrix
%   
%   CABLEUNITVECTOR: Normalized vector for each cable from attachment point
%   to its corrected pulley point as 3xM matrix
%   
%   CABLEWRAPANGLES: Matrix of gamma and beta angles of rotation and
%   wrapping angle of pulley and cable on pulley respectively, given as 2xM
%   matrix
% 
% Author: Philipp Tempel <philipp.tempel@isw.uni-stuttgart.de>
% Date: 2015-04-22
% Changelog:
%   2015-04-22: Initial release



%% Initialize variables
% To unify variable names
aCableAttachments = CableAttachments;
aPulleyPositions = PulleyPositions;
% Get the number of wires
nNumberOfCables = size(aPulleyPositions, 2);
% Holds the actual cable vector
% aCableVector = zeros(3, nNumberOfCables);
% Holds the normalized cable vector
aCableVectorUnit = zeros(3, nNumberOfCables);
% Holds the cable lengths
vCableLength = zeros(1, nNumberOfCables);
% Extract the position from the pose
vPlatformPosition = reshape(Pose(1:3), 3, 1);
% Extract rotatin from the pose
aPlatformRotation = reshape(Pose(4:12), 3, 3).';
% Get the gravity constant (7th argument) to the given value
if nargin >= 7
    dGravityConstant = GravityConstant;
% Gravity constant not set so set a default value
else
    dGravityConstant = 9.81;
end
% Get the cable properties struct
stCableProperties = CableProperties;
% And extract its fields
dCablePropYoungsModulus = stCableProperties.YoungsModulus;
dCablePropUnstrainedSection = stCableProperties.UnstrainedSection;
dCablePropDensity = stCableProperties.Density;

nDiscretizationPoints = 10e3;
aCableShape = zeros(2, nDiscretizationPoints, nNumberOfCables);



%% Initialize some local variables
% To quickly access the x coordinates of forces in the cable frame in the
% optimization vector
nIndexForcesX = 1:3:(3*nNumberOfCables);
% To quickly access the z coordinates of forces in the cable frame in the
% optimization vector
nIndexForcesZ = 2:3:(3*nNumberOfCables);
% To quickly access the cable lenghts in the optimization vector
nIndexLength = 3:3:(3*nNumberOfCables);
% Anchor positions in cable frame C are needed for the nonlinear equality
% constraints of the optimizer
aAnchorPositionsInC = zeros(3, nNumberOfCables);
% Angles of the rotation of each pulley
vPulleyAngles = zeros(1, nNumberOfCables);
% Transformation to get the proper values from the optimization variable x (we
% need only F_x and F_z) to be used in the linear equality and ineqaulity
% constraints
aSelectForcesFromOptimVectorAndTransformTo3D = [-1,0,0; 0,0,0; 0,-1,0];



%% Initialize the parameters for the optimization function
% This is the state we will perform optimziation over which is
% [F_x1 F_z1 L_01, F_x2 F_z2 L_02, ..., F_xm F_zm L_0z]
vInitialStateForOptimization = zeros(3*nNumberOfCables, 1);

%%% Linear equality constraints Ax = b
% Linear equality constraints matrix A
aLinearEqualityConstraints = zeros(6, 3*nNumberOfCables);
% Linear equality constraints vector b
vLinearEqualityConstraints = zeros(6, 1) - Wrench;


%%% Linear inequality constraints Ax <= b
% Linear inequality constraints matrix A
aLinearInequalityConstraints = zeros(6, 3*nNumberOfCables);
% Linear inequality constraints vector b
vLinearInequalityConstraints = zeros(6, 1);

% To populate the initial cable lengths and forces, we will use the straight
% line to get initial values
[vInitialLength, aInitCableUnitVector] = inverseKinematics(Pose, aPulleyPositions, aCableAttachments);
vInitialStateForOptimization(nIndexLength) = vInitialLength;

% Initial guessing of the force distribution is necessary, too
vInitForceDistribution = algoForceDistribution_AdvancedClosedForm(Wrench, getStructureMatrix(aCableAttachments, aInitCableUnitVector, aPlatformRotation), min(CableForceLimits), max(CableForceLimits));

%%% Boundaries
% Lower boundaries: Forces are not bound but the minimum cable length is set to
% 0
vLowerBoundaries = -Inf(3*nNumberOfCables, 1);
vLowerBoundaries(nIndexLength) = 0;

% Upper boundaries: Totally unlimited
vUpperBoundaries = Inf(3*nNumberOfCables, 1);

% Optimization target function
inOptimizationTargetFunction = @(x) norm(reshape(x(nIndexLength), nNumberOfCables, 1) - vInitialLength(:)) + norm(vInitForceDistribution - sqrt(x(nIndexForcesX).^2 + x(nIndexForcesZ).^2));


%% Do the magic
% Loop over every pulley and calculate the corrected pulley position i.e.,
% a_{i, corr}
for iCable = 1:nNumberOfCables
    dOffsetColumn = (iCable - 1)*3;
    
    % Get the line from Ai to Bi to determine its rotation about the z-axis
    % regarding K0's z-axis
    vA2B_in_0 = ( vPlatformPosition + aPlatformRotation*aCableAttachments(:,iCable) ) - aPulleyPositions(:,iCable);
    
    % Angle of rotation of the frame C about z_0 in degree
    dRotationAngleAbout_kCz_Degree = atan2d(vA2B_in_0(2), vA2B_in_0(1));
    vPulleyAngles(1,iCable) = dRotationAngleAbout_kCz_Degree;
    
    % Rotation matrix about K_C
    aRotation_kC2k0 = rotz(dRotationAngleAbout_kCz_Degree);
    
    % Anchor positions in C
    aAnchorPositionsInC(:,iCable) = transpose(aRotation_kC2k0)*(vPlatformPosition + aPlatformRotation*aCableAttachments(:,iCable) - aPulleyPositions(:,iCable));
    
    % Forces
    aLinearEqualityConstraints(1:3,(1:3) + dOffsetColumn) = aRotation_kC2k0*aSelectForcesFromOptimVectorAndTransformTo3D;
    
    % Torques are b_i(in 0) \times R_z(gamma) * Selector-from-x * x
    aLinearEqualityConstraints(4:6,(1:3) + dOffsetColumn) = vec2skew(aPlatformRotation*aCableAttachments(:,iCable))*aRotation_kC2k0*aSelectForcesFromOptimVectorAndTransformTo3D;
    
    % From the initial guess, get the forces of the cables on the anchor points
    % in the cable local frame
    vForceOfBiInC = transpose(aRotation_kC2k0)*(-aInitCableUnitVector(:,iCable)).*vInitForceDistribution(iCable);
    vInitialStateForOptimization(nIndexForcesX(iCable)) = vForceOfBiInC(1);
    vInitialStateForOptimization(nIndexForcesZ(iCable)) = vForceOfBiInC(3);
end

%% Run optimization
[xFinal, fval, exitflag, output] = fmincon(inOptimizationTargetFunction, vInitialStateForOptimization, ...
    aLinearInequalityConstraints, vLinearInequalityConstraints, ...
    aLinearEqualityConstraints, vLinearEqualityConstraints, ...
    vLowerBoundaries, vUpperBoundaries, ...
    @(vOptimizationVector) algoInverseKinematics_Catenary_nonlinearBoundaries(vOptimizationVector, aAnchorPositionsInC, dCablePropYoungsModulus, dCablePropUnstrainedSection, dCablePropDensity, dGravityConstant, min(CableForceLimits), max(CableForceLimits)));

% Extract the solutions from the final optimized vector
% Forces X
vCableForcesX = xFinal(nIndexForcesX);
% Forces Z
vCableForcesZ = xFinal(nIndexForcesZ);
% Cable length
vCableLength = xFinal(nIndexLength);


%% Output parsing
% First output is the cable lengths
length = vCableLength;

% Further outputs as requested
% Second output is the matrix of normalized cable vectors
if nargout >= 2
    % To get the cable force unit vectors we will have to take the forces of the
    % cables and transform them from the C frame to the 0 frame
    for iCable = 1:nNumberOfCables
        % Get the rotation matrix from C to 0
        aRotation_kC2k0 = rotz(vPulleyAngles(1, iCable));
        
        % Get the force vector in C
        vForceVector_in_C = [vCableForcesX(iCable), 0, vCableForcesZ(iCable)]';
        
        vForceVector_in_0 = aRotation_kC2k0*vForceVector_in_C;
        
        aCableVectorUnit(:,iCable) = -vForceVector_in_0./norm(vForceVector_in_0);
    end
    
    varargout{1} = aCableVectorUnit;
end

% Third output is the angle of rotation of the cable local frame relative to the
% world frame
if nargout >= 3
    varargout{2} = vPulleyAngles;
end

% Fourth output will be the revolving and wrapping angles of the
% pulleys
if nargout >= 4
    % Calculate the cable coordinates for the catenary line
    for iCable = 1:nNumberOfCables
        vLinspaceCableLength = linspace(0, vCableLength(iCable), nDiscretizationPoints);
        aCableShape(1,:,iCable) = vCableForcesX(iCable).*vLinspaceCableLength./(dCablePropYoungsModulus*dCablePropUnstrainedSection) ...
            + abs(vCableForcesX(iCable))./(dCablePropDensity.*dGravityConstant).*(asinh((vCableForcesZ(iCable) + dCablePropDensity.*dGravityConstant.*(vLinspaceCableLength - vCableLength(iCable)))./vCableForcesX(iCable)) - asinh((vCableForcesZ(iCable) - dCablePropDensity.*dGravityConstant.*vCableLength(iCable))./vCableForcesX(iCable)));
        
        aCableShape(2,:,iCable) = vCableForcesZ(iCable)./(dCablePropYoungsModulus.*dCablePropUnstrainedSection).*vLinspaceCableLength ...
            + dCablePropDensity.*dGravityConstant./(dCablePropYoungsModulus.*dCablePropUnstrainedSection).*(vLinspaceCableLength./2 - vCableLength(iCable)).*vLinspaceCableLength ...
            + 1./(dCablePropDensity.*dGravityConstant)*(sqrt(vCableForcesX(iCable).^2 + (vCableForcesZ(iCable) + dCablePropDensity.*dGravityConstant.*(vLinspaceCableLength - vCableLength(iCable))).^2) - sqrt(vCableForcesX(iCable).^2 + (vCableForcesZ(iCable) - dCablePropDensity.*dGravityConstant.*vCableLength(iCable)).^2));
    end
    
    varargout{3} = aCableShape;
end


end


function [c, ceq] = algoInverseKinematics_Catenary_nonlinearBoundaries(vOptimizationVector, aAnchorPositionsInC, dCablePropYoungsModulus, dCablePropUnstrainedCableSection, dCablePropDensity, dGravity, dForceMinimum, dForceMaximum)

%% Quickhand variables
% Number of wires
nNumberOfCables = size(aAnchorPositionsInC, 2);
% For forces F_x
vForcesX = vOptimizationVector(1:3:end);
% For forces F_z
vForcesZ = vOptimizationVector(2:3:end);
% Length L_0 components
vLength = vOptimizationVector(3:3:end);


%% Initialize the output variables
% Nonlinear inequality constraints are f_max and f_min
c = zeros(nNumberOfCables*2, 1);
% Nonlinear equality constraints are x_{end, i} and z_{end, i}
ceq = zeros(nNumberOfCables*2, 1);


%% Do the magic
% Set the equality constraints
for iCable = 1:nNumberOfCables
    dOffset = (iCable-1)*2;
    
    %%% Equalities
    % Position x
    ceq(iCable + 0 + dOffset) = vForcesX(iCable)*vLength(iCable)/(dCablePropYoungsModulus*dCablePropUnstrainedCableSection) ...
        + abs(vForcesX(iCable))/(dCablePropDensity*dGravity)*(asinh(vForcesZ(iCable)/vForcesX(iCable)) - asinh((vForcesZ(iCable) - dCablePropDensity*dGravity*vLength(iCable))/vForcesX(iCable))) ...
        - aAnchorPositionsInC(1, iCable);
    % Position z
    ceq(iCable + 1 + dOffset) = vForcesZ(iCable)*vLength(iCable)/(dCablePropYoungsModulus*dCablePropUnstrainedCableSection) ...
        - dCablePropDensity*dGravity*vLength(iCable)^2/(2*dCablePropYoungsModulus*dCablePropUnstrainedCableSection) ...
        + 1/(dCablePropDensity*dGravity)*(sqrt(vForcesX(iCable)^2 + vForcesZ(iCable)^2) - sqrt(vForcesX(iCable)^2 + (vForcesZ(iCable) - dCablePropDensity*dGravity*vLength(iCable))^2)) ...
        - aAnchorPositionsInC(3, iCable);
    
    %%% Inequalities
    % Min force
    c(iCable + 0 + dOffset) = dForceMinimum - sqrt(vForcesX(iCable)^2 + vForcesZ(iCable)^2);
    % Max force
    c(iCable + 1 + dOffset) = sqrt(vForcesX(iCable)^2 + vForcesZ(iCable)^2) - dForceMaximum;
end

end

%------------- END OF CODE --------------
% Please send suggestions for improvement of this file to the original
% author as can be found in the header
% Your contribution towards improving this funciton will be acknowledged in
% the "Changes" section of the header