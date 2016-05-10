function Row = rotationMatrixToRow(Matrix)%#codegen
% ROTATIONMATRIXTOROW converts a 3d rotation matrix to a row
% 
%   ROW = ROTATIONMATRIXTOROW(MATRIX) converts the 3x3 matrix into a 1x9
%   rotation vector
%   
%   
%   Inputs:
%   
%   MATRIX: The 3x3 rotation matrix in form of
%   [R11 R12 R13; ...
%    R21 R22 R23; ...
%    R31 R32 R33];
% 
%   Outputs:
% 
%   ROW: The 1x9 row vector representing the rows of MATRIX append to each other
%   like ROW = [R11 R12 R13 R21 R22 R23 R31 R32 R33]
%

warning('ROTATIONMATRIXTOROW function is obsolete. Use the ROTM2ROW function instead');



%% File information
% Author: Philipp Tempel <philipp.tempel@isw.uni-stuttgart.de>
% Date: 2016-05-10
% Changelog:
%   2016-05-10
%       * Add END OF CODE block
%   2016-05-09
%       * Deprecate function in favor of shorter method name `rowm2row`
%   2016-05-01
%       * Update to using permute instead of transpose
%   2015-08-07
%       * Initial release



%% Transformation
Row = rotm2row(Matrix);
% Row = reshape(permute(Matrix, [2, 1]), 1, 9);


end

%------------- END OF CODE --------------
% Please send suggestions for improvement of this file to the original
% author as can be found in the header
% Your contribution towards improving this function will be acknowledged in
% the "Changes" section of the header
