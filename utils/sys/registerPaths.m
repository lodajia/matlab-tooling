function registerPaths(varargin)

% Get the paths to be added
cePaths = varargin;
% Get list of all paths registered
cePathList = regexp(path, pathsep, 'Split');

% Get the current debug stack so we don't recursively call startup of the same
% file
stStack = dbstack('-completenames');
% Get all the filenames from the current stack so that access later on is easier
ceFileStack = {stStack.file};

% Loop over every path-to-be-added
for iPath = numel(cePaths):-1:1
    % Extract current path form list of paths (faster because we'll be needing
    % it a few more times)
    chPath = cePaths{iPath};
    
    % If the path given is a string generated by genpath, then we will need to
    % split that by ';'
    if strfind(chPath, pathsep)
        % Split this path into each of its subpaths
        cePathPathList = regexp(chPath, pathsep, 'Split');
        
        % Try adding each of the paths inside this path list separately
        try
            registerPaths(cePathPathList{:});
        catch ME
            warning(ME.message);
        end
    % Just a single path given
    else
        % Get path's canonical name i.e., turn any relative path into an absolute
        % path
        % @see http://stackoverflow.com/questions/18395892/how-to-resolve-a-relative-directory-path-to-canonical-path-in-matlab-octave
        jFile = java.io.File(chPath);
        chPath = char(jFile.getCanonicalPath);

        % Only add the path if it isn't already added
        if ( ~all(ismember(chPath, cePathList)) && 0 ~= exist(chPath, 'dir') )
            % Try adding the folder to the path. If things fail here, we'll be save
            % because we're just TRYing to add the folder so a failure won't break
            % the whole script
            try
                % Add the path
                addpath(chPath);
                % Startup file path
                chStartupFile = fullfile(chPath, 'startup.m');
                % Startup file exists and we're not calling the same startup file
                % that we are currently being called from?
                if 0 ~= exist(chStartupFile, 'file') && ~ismember(chStartupFile, ceFileStack)
                    % Execute it
                    run(chStartupFile);
                end
            catch ME
                warning(ME.message);
            end
        end
    end
end

end